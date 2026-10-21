// 書き出し用の HTML を作る（元：daihon の lua/daihon/export.lua）。ファイルや画面には触らない（塊の中身は getPart で受け取る）
import { parse, trim } from "./parse.js";
import { format as formatCount } from "./count.js";

const MAX_DEPTH = 10;

// 組み込みの塊（parts/ ではなく、書き出すときに作る）
export const BUILTINS = new Set(["@文字数一覧"]);

/** Lua の string.format の %s と %% だけを読む（見出しの show 用） */
function formatShow(pattern, args) {
  let i = 0;
  return pattern.replace(/%([s%])/g, (_, c) => (c === "%" ? "%" : String(args[i++])));
}

/** 見出しの文字（count の見出しは show の形で文字数を付ける） */
function headingText(r, n) {
  if (n !== undefined && r.heading.show) return formatShow(r.heading.show, [r.title, formatCount(n)]);
  return r.title;
}

/** 書き出す行のクラス名（CSS で見た目を変えるときに使う） */
export function classOf(r) {
  if (r.kind === "セリフ") return "serifu";
  return (r.type && r.type.class) || `t-${r.kind}`;
}

/**
 * 書き出す中身を、形式によらない並びにする
 * opts = { togaki: true（ト書きも出す）, getPart, summary（count.summary の結果）, vertical（縦書きか） }
 * 返す値：{ items, missing }。items の1つは次のどれか
 *   { kind: "heading", level, text, new_page }
 *   { kind: "line", class, text, speaker, togaki }
 *   { kind: "gap" }（空行の空き）
 *   { kind: "count_list", rows: [文字, ...], total: 文字 }（{@文字数一覧}）
 */
export function items(records, cfg, opts) {
  const pdf = cfg.export.pdf;
  const out = [];
  const missing = [];
  // 空行の空きは、次に本文が来たときだけ入れる（続けても1つ、見出しの前と最後には入れない）
  let started = false;
  let pendingGap = false;
  const getPart = (name) => (opts.getPart ? opts.getPart(name) : undefined);

  const push = (item) => {
    if (pendingGap) out.push({ kind: "gap" });
    out.push(item);
    started = true;
    pendingGap = false;
  };

  const line = (r, text) =>
    push({ kind: "line", class: classOf(r), text, speaker: r.speaker, togaki: r.kind !== "セリフ" });

  const partInline = (name) => {
    const lines = getPart(name);
    if (!lines) {
      missing.push(name);
      return `{${name}}`;
    }
    return lines.join(" ");
  };

  const countList = () => {
    const rows = [];
    for (const r of records) {
      const n = opts.summary.headings[r.lnum];
      if (n !== undefined) rows.push(headingText(r, n));
    }
    return { kind: "count_list", rows, total: `合計 : ${formatCount(opts.summary.total)}文字` };
  };

  const emit = (recs, depth) => {
    for (const r of recs) {
      const refs = r.refs || [];
      const alone = refs.length === 1 && trim(r.text) === refs[0].match;

      if (r.kind === "空行") {
        pendingGap = started;
      } else if (r.kind === "塊開始" || r.kind === "塊終了" || !(r.kind === "見出し" || r.output)) {
        // 目印とメモは出さない
      } else if (r.kind === "見出し") {
        const n = depth === 0 && opts.summary ? opts.summary.headings[r.lnum] : undefined;
        out.push({
          kind: "heading",
          level: Math.min(r.level, 6),
          text: headingText(r, n),
          new_page: pdf.new_page ? r.level <= pdf.new_page : false,
        });
        started = false;
        pendingGap = false;
      } else if (r.kind !== "セリフ" && !opts.togaki) {
        // ト書きなし
      } else if (alone && refs[0].name === "@文字数一覧") {
        push(countList());
      } else if (alone && depth < MAX_DEPTH) {
        const lines = getPart(refs[0].name);
        if (lines) {
          emit(parse(lines, cfg), depth + 1);
        } else {
          missing.push(refs[0].name);
          line(r, r.text);
        }
      } else {
        let text = trim(r.text).replace(/\{([^{}]+)\}/g, (_, name) => partInline(trim(name)));
        const marks = opts.vertical && pdf.vertical_marks;
        if (r.range && marks && marks[r.range.op]) {
          // 縦書きでは ▼▲ を読む向きに合う記号にする
          const i = text.indexOf(r.range.mark);
          if (i >= 0) text = text.slice(0, i) + marks[r.range.op] + text.slice(i + r.range.mark.length);
        }
        line(r, text);
      }
    }
  };

  emit(records, 0);
  return { items: out, missing };
}

const escapeHtml = (s) =>
  s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

/** 縦書きで1〜2桁の数字を縦中横にする */
const tcy = (s) => s.replace(/(?<![0-9])([0-9]{1,2})(?![0-9])/g, '<span class="tcy">$1</span>');

/**
 * 台本を HTML にする
 * opts = { togaki: true（ト書きも出す）, getPart, title: 題, css: 文字列, summary: count.summary の結果 }
 * 返す値：{ html, missing }（missing＝未登録の塊の名前）
 */
export function build(records, cfg, opts) {
  const pdf = cfg.export.pdf;
  const vertical = pdf.vertical !== false;
  const { items: list, missing } = items(records, cfg, { ...opts, vertical });

  const textHtml = (s) => (vertical ? tcy(escapeHtml(s)) : escapeHtml(s));

  const body = [];
  for (const it of list) {
    if (it.kind === "gap") {
      body.push('<p class="gap"></p>');
    } else if (it.kind === "heading") {
      const cls = it.new_page ? ' class="new-page"' : "";
      body.push(`<h${it.level}${cls}>${textHtml(it.text)}</h${it.level}>`);
    } else if (it.kind === "count_list") {
      body.push('<div class="count-list">');
      for (const row of it.rows) body.push(`<p class="count-row">${textHtml(row)}</p>`);
      body.push(`<p class="count-total">${textHtml(it.total)}</p>`);
      body.push("</div>");
    } else {
      let html = textHtml(it.text);
      if (it.speaker !== undefined) {
        const name = textHtml(it.speaker);
        if (html.startsWith(name)) html = `<span class="speaker">${name}</span>` + html.slice(name.length);
      }
      body.push(`<p class="${it.class}">${html}</p>`);
    }
  }

  const html = [
    "<!doctype html>",
    '<html lang="ja">',
    "<head>",
    '<meta charset="utf-8">',
    `<title>${escapeHtml(opts.title ?? "台本")}</title>`,
    "<style>",
    css(pdf),
    opts.css ?? "",
    "</style>",
    "</head>",
    "<body>",
    body.join("\n"),
    "</body>",
    "</html>",
    "",
  ].join("\n");
  return { html, missing };
}

const or = (v, fallback) => (v === undefined || v === null || v === false ? fallback : v);

/** 既定の見た目。export.pdf の値から作る。細かい所は export.pdf.css の自分の CSS で上書きする */
export function css(pdf) {
  const vertical = pdf.vertical !== false;
  const pageNumber =
    pdf.page_number !== false
      ? "@bottom-center { content: counter(page); font-size: 9pt; writing-mode: horizontal-tb; }"
      : "";
  return [
    `@page { size: ${or(pdf.size, "A4 landscape")}; margin: ${or(pdf.margin, "20mm")}; ${pageNumber} }`,
    "html {",
    vertical ? "  writing-mode: vertical-rl;" : "",
    `  font-family: ${or(pdf.font, "serif")};`,
    `  font-size: ${or(pdf.font_size, "11pt")};`,
    `  line-height: ${or(pdf.line_height, 1.8)};`,
    "}",
    "body { margin: 0; }",
    "p { margin: 0; }",
    "h1 { font-size: 1.6em; margin-block: 0 1em; }",
    "h2 { font-size: 1.25em; margin-block: 1em; }",
    ".new-page { break-before: page; }",
    // 見出しが続く所と、最初の見出しでは改ページしない
    ".new-page + .new-page, body > .new-page:first-child { break-before: auto; }",
    ".gap { block-size: 0; margin-block-end: 1em; }",
    // ト書きは行の頭、セリフは1段下げる
    `.serifu { padding-inline-start: ${or(pdf.serifu_indent, "3em")}; }`,
    ".t-指示 { font-size: 0.9em; color: #555; }",
    ".speaker { font-weight: bold; }",
    ".tcy { text-combine-upright: all; }",
    ".count-list { margin-block: 1em; }",
    ".count-total { font-weight: bold; }",
  ].join("\n");
}
