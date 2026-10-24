// ページの枠（SE・コメントと演技指示・その他・縦横・ルビ）と、設定（daihon.json の形）を行き来する。画面には触らない
import { merge, defaults } from "./config.js";

const asList = (x) => (x === undefined || x === null ? [] : Array.isArray(x) ? x : [x]);
const isTable = (t) => t !== null && typeof t === "object" && !Array.isArray(t);
const clone = (v) => (v === undefined ? undefined : JSON.parse(JSON.stringify(v)));

// 枠と line_types の種類の対応。上から順に当てるので、SE（// SE）を指示（//）より先に置く
export const KINDS = [
  { key: "se", name: "SE", class: "t-指示" },
  { key: "shiji", name: "指示" },
  { key: "other", name: "メモ" },
];

// ページを開いたときの設定（daihon の書き方も、Google ドキュメントでよくある書き方も読む）
export const START = {
  line_types: [
    { name: "SE", prefix: ["// SE", "SE：", "SE:"], class: "t-指示" },
    { name: "指示", prefix: ["//", "(", "（", "【"] },
    { name: "メモ", prefix: ["¥", "￥"], output: false },
  ],
};

/** 枠に打った記号を分ける（、 , ， と改行で区切る） */
export const splitMarks = (s) =>
  String(s ?? "")
    .split(/[、,，\n]/)
    .map((x) => x.trim())
    .filter((x) => x !== "");

export const joinMarks = (list) => asList(list).join("、");

/** 設定から枠の中身を読む */
export function read(project) {
  const cfg = merge(defaults, project);
  const types = asList(cfg.line_types);
  const find = (name) => types.find((t) => t && t.name === name);
  const out = {};
  for (const k of KINDS) out[k.key] = joinMarks(find(k.name)?.prefix);
  out.otherOutput = find("メモ") ? find("メモ").output !== false : false;
  out.vertical = cfg.export.pdf.vertical !== false;
  const ruby = cfg.ruby;
  out.ruby = ruby
    ? { on: true, start: joinMarks(ruby.start), open: ruby.open ?? "", close: ruby.close ?? "", pixiv: !!ruby.pixiv }
    : { on: false, start: "", open: "", close: "", pixiv: false };
  // 枠に出ない種類（daihon.json で足した物）。設定には残す
  const names = new Set(KINDS.map((k) => k.name));
  out.extra = types.filter((t) => t && !names.has(t.name)).map((t) => t.name);
  return out;
}

/** 枠の中身を設定に書いた、新しい設定を返す（枠に無い種類・ほかの設定はそのまま） */
export function write(project, f) {
  const p = clone(project) ?? {};
  const cfg = merge(defaults, p);
  const types = asList(cfg.line_types);
  const names = new Set(KINDS.map((k) => k.name));

  const lineTypes = [];
  for (const k of KINDS) {
    const prefix = splitMarks(f[k.key]);
    if (prefix.length === 0) continue; // 空の枠は、その種類を使わない
    const old = types.find((t) => t && t.name === k.name) ?? {};
    const lt = { ...old, name: k.name, prefix };
    if (k.class && lt.class === undefined) lt.class = k.class;
    if (k.key === "other") lt.output = !!f.otherOutput;
    else delete lt.output;
    lineTypes.push(lt);
  }
  for (const t of types) if (t && !names.has(t.name)) lineTypes.push(t);
  p.line_types = lineTypes;

  // 縦書き・横書き。紙の大きさを書いていなければ、横書きは A4 縦にする
  p.export = isTable(p.export) ? p.export : {};
  p.export.pdf = isTable(p.export.pdf) ? p.export.pdf : {};
  const pdf = p.export.pdf;
  pdf.vertical = f.vertical !== false;
  if (!pdf.vertical && pdf.size === undefined) pdf.size = "A4 portrait";
  if (pdf.vertical && pdf.size === "A4 portrait") delete pdf.size;

  const r = f.ruby ?? {};
  p.ruby = r.on === false ? false : { start: splitMarks(r.start), open: r.open ?? "", close: r.close ?? "", pixiv: !!r.pixiv };
  return p;
}
