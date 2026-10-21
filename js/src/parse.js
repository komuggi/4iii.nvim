// 台本の行を種類に分ける（元：daihon の lua/daihon/parse.lua）。ファイルや画面には触らない
// 位置（col・s・e）は daihon と同じく UTF-8 のバイトで数える

const SPACE = "[ \\t\\n\\v\\f\\r\\u3000]"; // Lua の %s（ASCII の空白）と全角スペース
const TRIM = new RegExp(`^${SPACE}+|${SPACE}+$`, "g");
const encoder = new TextEncoder();

/** UTF-8 のバイト数 */
export const byteLength = (s) => encoder.encode(s).length;

const asList = (x) => (x === undefined || x === null ? [] : Array.isArray(x) ? x : [x]);
const listOf = (x) => (Array.isArray(x) ? x : []); // Lua の ipairs と同じ：リストでなければ何もない

/** 前後の空白（全角スペースを含む）を取る */
export const trim = (s) => s.replace(TRIM, "");

function matchPrefix(s, prefixes) {
  for (const p of asList(prefixes)) {
    if (p !== "" && s.startsWith(p)) return p;
  }
  return undefined;
}

function stripSuffix(s, suffixes) {
  for (const p of asList(suffixes)) {
    if (p !== "" && s.length >= p.length && s.endsWith(p)) return s.slice(0, s.length - p.length);
  }
  return s;
}

/** 行の中の {名前} を探す。s, e は行の中のバイト位置（1 始まり）、match は {名前} の字面 */
export function findRefs(line) {
  const refs = [];
  const re = /\{([^{}]+)\}/g;
  for (const m of line.matchAll(re)) {
    const before = line[m.index - 1] ?? "";
    const after = line[m.index + m[0].length] ?? "";
    if (before !== "{" && after !== "}") {
      const s = byteLength(line.slice(0, m.index)) + 1;
      refs.push({ name: trim(m[1]), s, e: s + byteLength(m[0]) - 1, match: m[0] });
    }
  }
  return refs;
}

/** 複数人のセリフから名前と中身を分ける。名前がなければ undefined */
function splitSpeaker(text, style) {
  const marks = style === "colon" ? ["：", ":"] : ["「"];
  for (const mark of marks) {
    const i = text.indexOf(mark);
    if (i > 0) {
      const name = trim(text.slice(0, i));
      let body = text.slice(i + mark.length);
      if (style === "kagi") body = stripSuffix(trim(body), "」");
      if (name !== "") return { name, body: trim(body), nameLength: byteLength(text.slice(0, i)) };
    }
  }
  return undefined;
}

/** ▼▲ のラベルを比べるための形（空白の違いは無視する） */
export const labelKey = (label) => label.replace(/[ \t\n\v\f\r]/g, "").replace(/　/g, "");

function findRange(body, ranges) {
  for (const op of ["open", "close"]) {
    const mark = ranges[op];
    if (mark && body.startsWith(mark)) {
      const label = trim(body.slice(mark.length));
      return { op, mark, label, key: labelKey(label) };
    }
  }
  return undefined;
}

/**
 * 行を1つずつ種類に分ける
 * 返す配列：{ lnum, text, kind, body, output, ... }
 *   kind = "空行" | "見出し" | "塊開始" | "塊終了" | "範囲" | "セリフ" | line_types の name
 */
export function parse(lines, cfg) {
  const records = [];
  const ranges = cfg.ranges || {};
  const rangeTypes = new Set(listOf(ranges.in_types));
  let inBlock;

  lines.forEach((line, idx) => {
    const r = { lnum: idx + 1, text: line };
    const t = trim(line);
    const lead = t === "" ? 0 : byteLength(line.slice(0, line.indexOf(t)));

    if (t === "") {
      r.kind = "空行";
    } else if (t.startsWith("{{")) {
      r.kind = "塊開始";
      r.block_name = trim(t.slice(2));
      inBlock = r.block_name;
    } else if (t === "}}" && inBlock !== undefined) {
      r.kind = "塊終了";
      r.block_name = inBlock;
      inBlock = undefined;
    } else {
      r.in_block = inBlock;
      for (const h of listOf(cfg.headings)) {
        const p = matchPrefix(t, h.prefix);
        if (p !== undefined) {
          r.kind = "見出し";
          r.heading = h;
          r.level = h.level;
          r.title = trim(t.slice(p.length));
          break;
        }
      }
      if (!r.kind) {
        // 行の頭に ▼▲ を直接書いた行は、範囲だけの行
        const rg = findRange(t, ranges);
        if (rg) {
          r.kind = "範囲";
          r.output = true;
          r.body = t;
          r.range = { ...rg, col: lead };
        }
      }
      if (!r.kind) {
        for (const lt of listOf(cfg.line_types)) {
          const p = matchPrefix(t, lt.prefix);
          if (p !== undefined) {
            r.kind = lt.name;
            r.type = lt;
            r.output = lt.output !== false;
            r.body = trim(stripSuffix(trim(t.slice(p.length)), lt.suffix));
            if (rangeTypes.has(lt.name)) {
              const rg = findRange(r.body, ranges);
              if (rg) {
                const leadChars = line.indexOf(t);
                const at = line.indexOf(rg.mark, leadChars);
                r.range = { ...rg, col: byteLength(line.slice(0, at)) };
              }
            }
            break;
          }
        }
      }
      if (!r.kind) {
        r.kind = "セリフ";
        r.output = true;
        r.body = t;
        if (cfg.mode === "multi") {
          const sp = splitSpeaker(t, cfg.multi && cfg.multi.style);
          if (sp) {
            r.speaker = sp.name;
            r.speaker_col = [lead, lead + sp.nameLength];
            r.body = sp.body;
          }
        }
      }
      r.refs = findRefs(line);
    }
    records.push(r);
  });
  return records;
}

/** 閉じのラベルに当たる「開いている ▼」を探す（何番目か・0 始まり）。同じラベルを優先し、なければ頭が同じもの */
export function findOpen(open, key) {
  for (let k = open.length - 1; k >= 0; k--) {
    if (open[k].key === key) return k;
  }
  if (key === "") return undefined;
  for (let k = open.length - 1; k >= 0; k--) {
    if (open[k].key.startsWith(key)) return k;
  }
  return undefined;
}

/** ▼▲ を上からたどる。範囲は重ねてよい。stop を渡すとその行の手前で開いているものを返す。issues に警告を足す */
function walkRanges(records, cfg, stop, issues) {
  const ranges = cfg.ranges || {};
  const openMark = ranges.open || "";
  const closeMark = ranges.close || "";
  let open = [];

  const flush = (where) => {
    if (issues) {
      for (const o of open) {
        issues.push({
          lnum: o.lnum,
          col: o.col,
          msg: `${openMark}${o.label} が閉じていません（${where}までに ${closeMark}${o.label} が要ります）`,
        });
      }
    }
    open = [];
  };

  for (const r of records) {
    if (stop !== undefined && r.lnum >= stop) return open;
    if (r.kind === "見出し") {
      flush("次の見出し");
    } else if (r.range && r.range.op === "open") {
      open.push({ label: r.range.label, key: r.range.key, lnum: r.lnum, col: r.range.col });
    } else if (r.range && r.range.op === "close") {
      const k = findOpen(open, r.range.key);
      if (k !== undefined) {
        open.splice(k, 1);
      } else if (issues) {
        issues.push({
          lnum: r.lnum,
          col: r.range.col,
          msg: `${closeMark}${r.range.label} に対応する ${openMark}${r.range.label} がありません`,
        });
      }
    }
  }
  if (stop === undefined) flush("ファイルの終わり");
  return open;
}

/** ▼▲ の対応を確かめる。返す配列：{ lnum, col, msg } */
export function checkRanges(records, cfg) {
  const issues = [];
  walkRanges(records, cfg, undefined, issues);
  return issues;
}

/** lnum 行目の手前で開いている ▼ の一覧（開いた順） */
export const openRangesAt = (records, cfg, lnum) => walkRanges(records, cfg, lnum);
