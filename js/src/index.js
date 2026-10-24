// daihon-pdf の部品：台本の文字列 → 縦書きの HTML（ト書きあり／なし）
// CLI（bin/daihon-pdf.js）とブラウザのページ（web/）の両方がここを使う
import { makeConfig } from "./config.js";
import { parse } from "./parse.js";
import { context, summary } from "./count.js";
import { build } from "./export.js";

export * as config from "./config.js";
export * as parser from "./parse.js";
export * as counter from "./count.js";
export * as exporter from "./export.js";
export * as hankaku from "./hankaku.js";
export * as ruby from "./ruby.js";
export * as fields from "./fields.js";
export { makeConfig };

/** 塊の名前に使えるか（元：daihon の blocks.lua の valid_name。ファイル名になるので / や先頭の . はだめ） */
export function validPartName(name) {
  return name !== "" && !/[/\\]/.test(name) && !name.startsWith(".") && new TextEncoder().encode(name).length <= 100;
}

/** 文字列を行に分ける（nvim の readfile と同じ：先頭の BOM と、改行の前の CR を取る。最後の改行のあとは行にしない） */
export function splitLines(text) {
  let s = text.startsWith("﻿") ? text.slice(1) : text;
  s = s.replace(/\r\n/g, "\n");
  if (s === "") return [];
  const lines = s.split("\n");
  if (lines[lines.length - 1] === "") lines.pop();
  return lines;
}

/**
 * 台本を HTML にする（ト書きあり／なし）
 * text：台本の文字列（または行の配列）
 * cfg：makeConfig() で作った設定
 * opts = { name: ファイル名のもと（既定 "台本"）, getPart(name) → 行の配列か undefined, css: 自分の CSS の文字列 }
 * 返す値：{ outputs: [{ name, togaki, html }], missing: [未登録の塊の名前], summary }
 * export.pdf.both が false なら、ト書きありの1つだけ
 */
export function render(text, cfg, opts = {}) {
  const lines = Array.isArray(text) ? text : splitLines(text);
  const records = parse(lines, cfg);
  const sum = summary(records, context(cfg, opts.getPart));
  const base = opts.name ?? "台本";
  const variants = [["ト書きあり", true]];
  if (cfg.export.pdf.both) variants.push(["ト書きなし", false]);

  const outputs = [];
  const missing = new Set();
  for (const [label, togaki] of variants) {
    const name = `${base}_${label}`;
    const res = build(records, cfg, { togaki, title: name, css: opts.css, summary: sum, getPart: opts.getPart });
    res.missing.forEach((m) => missing.add(m));
    outputs.push({ name, togaki, html: res.html });
  }
  return { outputs, missing: [...missing].sort(), summary: sum, records };
}
