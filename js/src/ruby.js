// ルビを読む。ファイルや画面には触らない
// 読む形（記号は設定の ruby で変えられる。ruby = false でルビを読まない）
//   |漢字《かんじ》 … | から 《 までに付ける（｜ も同じ）
//   漢字《かんじ》  … | が無いときは 《 の前に続く漢字に付ける
//   [[rb:漢字 > かんじ]] … pixiv の形（ruby.pixiv）

const KANJI = "[\\p{Script=Han}々〆〇ヶ]";
const escapeRe = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
const asList = (x) => (x === undefined || x === null ? [] : Array.isArray(x) ? x : [x]);
const isText = (s) => typeof s === "string" && s !== "";

/** 設定から、ルビを探す正規表現を作る。ルビを読まないなら undefined */
function pattern(ruby) {
  if (!ruby || typeof ruby !== "object") return undefined;
  const alts = [];
  if (ruby.pixiv) alts.push("\\[\\[rb:\\s*([^>\\]]+?)\\s*>\\s*([^\\]]+?)\\s*\\]\\]");
  if (isText(ruby.open) && isText(ruby.close)) {
    const o = escapeRe(ruby.open);
    const c = escapeRe(ruby.close);
    const starts = asList(ruby.start).filter(isText).map(escapeRe);
    if (starts.length > 0) {
      const stop = [o, ...starts].join("|");
      alts.push(`(?:${starts.join("|")})((?:(?!${stop}).)+?)${o}((?:(?!${c}).)+?)${c}`);
    }
    alts.push(`(${KANJI}+)${o}((?:(?!${c}).)+?)${c}`);
  }
  return alts.length > 0 ? new RegExp(alts.join("|"), "gu") : undefined;
}

/** 文を並びに分ける。返す配列：{ text } か { base, reading } */
export function split(s, ruby) {
  const re = pattern(ruby);
  if (!re) return [{ text: s }];
  const out = [];
  let last = 0;
  for (const m of s.matchAll(re)) {
    if (m.index > last) out.push({ text: s.slice(last, m.index) });
    // どの形に当たったか：() の組のうち、値のある最初の組
    let k = 1;
    while (m[k] === undefined) k += 2;
    out.push({ base: m[k], reading: m[k + 1] });
    last = m.index + m[0].length;
  }
  if (last < s.length) out.push({ text: s.slice(last) });
  return out;
}

/** ルビの記号と読みを除いた文（文字数を数えるとき） */
export const plain = (s, ruby) => split(s, ruby).map((p) => p.text ?? p.base).join("");
