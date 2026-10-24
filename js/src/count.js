// 文字数を数える（元：daihon の lua/daihon/count.lua）。ファイルや画面には触らない（塊の中身は getPart で外から受け取る）
import { parse } from "./parse.js";
import { plain } from "./ruby.js";

const MAX_DEPTH = 10; // 塊の中の塊をたどる深さの上限（ループよけ）
const isSpace = (ch) => /^[ \t\n\v\f\r]$/.test(ch) || ch === "　";

export function charSet(s) {
  return new Set(Array.from(s || ""));
}

/** 空白・改行と ignore の記号を除いた文字数（1文字＝1つのコードポイント） */
export function chars(s, ignore) {
  let n = 0;
  for (const ch of s) {
    if (!(isSpace(ch) || (ignore && ignore.has(ch)))) n += 1;
  }
  return n;
}

/** 3369 → "3,369" */
export function format(n) {
  return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}

const stripRefs = (s) => s.replace(/\{[^{}]+\}/g, "");
// 数える文：{名前} の字面とルビの読みは数えない
const countable = (s, cfg) => stripRefs(plain(s, cfg.ruby));

/**
 * 数えるための道具をまとめる
 * getPart(name) は塊の中身の行（配列）を返す。なければ undefined
 * include を渡すと cfg.count.include の代わりに使う
 */
export function context(cfg, getPart, include) {
  const kinds = include ?? (cfg.count && cfg.count.include) ?? ["セリフ"];
  const lines = new Map();
  const counts = new Map();
  const ctx = {
    cfg,
    include: new Set(Array.isArray(kinds) ? kinds : []),
    ignore: charSet(cfg.count && cfg.count.ignore_chars),
  };

  ctx.partLines = (name) => {
    if (!lines.has(name)) lines.set(name, (getPart && getPart(name)) || false);
    return lines.get(name) || undefined;
  };

  ctx.hasPart = (name) => ctx.partLines(name) !== undefined;

  ctx.partCount = (name, depth = 0) => {
    if (counts.has(name)) return counts.get(name);
    const partLines = ctx.partLines(name);
    if (!partLines || depth > MAX_DEPTH) return 0;
    counts.set(name, 0); // 自分自身を呼ぶ塊よけ
    let n = 0;
    for (const r of parse(partLines, cfg)) n += line(r, ctx, depth + 1);
    counts.set(name, n);
    return n;
  };

  return ctx;
}

/** 1行の文字数。{名前} は字面ではなく塊の中身で数える。出力しない行は 0 */
export function line(r, ctx, depth) {
  if (!r.output) return 0;
  let n = 0;
  if (ctx.include.has(r.kind) && r.body !== undefined) n = chars(countable(r.body, ctx.cfg), ctx.ignore);
  for (const ref of r.refs || []) n += ctx.partCount(ref.name, depth);
  return n;
}

/** limit 文字より長いセリフの行。返す配列：{ lnum, n }（{名前} の字面とルビの読みは数えない） */
export function longLines(records, ctx, limit) {
  const out = [];
  if (limit === false || limit === undefined || limit === null) return out;
  for (const r of records) {
    if (r.kind === "セリフ" && r.body !== undefined) {
      const n = chars(countable(r.body, ctx.cfg), ctx.ignore);
      if (n > limit) out.push({ lnum: r.lnum, n });
    }
  }
  return out;
}

/**
 * 全体と見出しごとの文字数
 * 返す値：{ total, lines: { [lnum]: n }, headings: { [lnum]: n } }
 */
export function summary(records, ctx) {
  const per = {};
  let total = 0;
  for (const r of records) {
    const n = line(r, ctx, 0);
    per[r.lnum] = n;
    total += n;
  }
  const headings = {};
  records.forEach((r, i) => {
    if (r.kind === "見出し" && r.heading.count) {
      let n = 0;
      for (let j = i + 1; j < records.length; j++) {
        const q = records[j];
        if (q.kind === "見出し" && q.level <= r.level) break;
        n += per[q.lnum];
      }
      headings[r.lnum] = n;
    }
  });
  return { total, lines: per, headings };
}
