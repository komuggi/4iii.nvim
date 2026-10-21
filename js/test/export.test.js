// 元の daihon の tests/test_export.lua のうち、HTML の所を写した物
import { test } from "node:test";
import assert from "node:assert/strict";
import { merge, defaults } from "../src/config.js";
import { parse } from "../src/parse.js";
import { context, summary } from "../src/count.js";
import { build } from "../src/export.js";
import { render, makeConfig, splitLines } from "../src/index.js";

const parts = { あいさつ: ["// ▼右・近", "おかえり"], 短い: ["またね"] };
const getPart = (n) => parts[n];

function html(lines, togaki, over) {
  const cfg = merge(defaults, over);
  const records = parse(lines, cfg);
  const sum = summary(records, context(cfg, getPart));
  return build(records, cfg, { togaki, getPart, summary: sum, title: "t" });
}

const has = (s, part) => assert.ok(s.includes(part), `ない: ${part}`);
const hasnt = (s, part) => assert.ok(!s.includes(part), `あってはいけない: ${part}`);
const countOf = (s, part) => s.split(part).length - 1;

test("書き出し：ト書きあり／なし。メモと塊の目印は出さない", () => {
  const lines = ["## Track 01", "(玄関)", "// SE : 足音", "ただいま", "¥ メモ", "{{短い", "またね", "}}"];
  const a = html(lines, true).html;
  has(a, '<p class="t-場面">(玄関)</p>');
  has(a, '<p class="t-指示">// SE : 足音</p>');
  has(a, '<p class="serifu">ただいま</p>');
  hasnt(a, "メモ");
  hasnt(a, "{{");
  const b = html(lines, false).html;
  hasnt(b, "玄関");
  hasnt(b, "足音");
  has(b, '<p class="serifu">ただいま</p>');
});

test("書き出し：見出しに文字数。{@文字数一覧}", () => {
  const s = html(["{@文字数一覧}", "# 本編", "## Track 01", "ただいま", "## Track 02", "{短い}"], true).html;
  has(s, 'Track <span class="tcy">01</span> : <span class="tcy">4</span>文字');
  has(s, '<p class="count-total">合計 : <span class="tcy">7</span>文字</p>');
  has(s, '<h2 class="new-page">');
});

test("書き出し：塊は中身に置き換える。1行なら行ごと、途中なら文の中に", () => {
  const a = html(["{あいさつ}", "また{短い}"], true).html;
  has(a, '<p class="t-指示">// ◀右・近</p>');
  has(a, '<p class="serifu">おかえり</p>');
  has(a, '<p class="serifu">またまたね</p>');
  hasnt(html(["{あいさつ}"], false).html, "右・近");
  assert.deepEqual(html(["{ない}"], true).missing, ["ない"]);
});

test("書き出し：HTML の記号は逃がす。横書きにもできる", () => {
  const s = html(["<b>&"], true, { export: { pdf: { vertical: false } } }).html;
  has(s, "&lt;b&gt;&amp;");
  hasnt(s, "vertical-rl");
  has(html(["あ"], true).html, "writing-mode: vertical-rl");
});

test("書き出し：空行は続けても1つ", () => {
  eq1(countOf(html(["あ", "", "", "// 指示", "", "い"], false).html, 'class="gap"'), 1);
});

test("書き出し：見出しの前と最後には空きを入れない", () => {
  eq1(countOf(html(["あ", "", "## Track 01", "", "い", ""], true).html, 'class="gap"'), 0);
});

test("書き出し：縦書きでは ▼▲ を ◀▶ にする。横書きと設定で外したときはそのまま", () => {
  const lines = ["// ▼前・中", "おかえり", "// ▲前・中", "// ▼と書いた文の中の▼"];
  const v = html(lines, true).html;
  has(v, "// ◀前・中");
  has(v, "// ▶前・中");
  has(v, "// ◀と書いた文の中の▼");
  has(html(lines, true, { export: { pdf: { vertical: false } } }).html, "// ▼前・中");
  has(html(lines, true, { export: { pdf: { vertical_marks: false } } }).html, "// ▼前・中");
});

test("書き出し：セリフは字下げ、ト書きは行の頭", () => {
  const s = html(["あ"], true).html;
  has(s, ".serifu { padding-inline-start: 3em; }");
  hasnt(s, ".t-指示 { padding-inline-start");
});

test("書き出し：1〜2桁の数字だけ縦中横", () => {
  const s = html(["1 と 12 と 123 と １"], true).html;
  has(s, '<span class="tcy">1</span> と <span class="tcy">12</span> と 123 と １');
});

test("render：ト書きあり／なしの2つ。both = false で1つ", () => {
  const two = render("ただいま\n", makeConfig({}), { name: "x" });
  assert.deepEqual(
    two.outputs.map((o) => o.name),
    ["x_ト書きあり", "x_ト書きなし"],
  );
  const one = render("ただいま\n", makeConfig({ export: { pdf: { both: false } } }));
  assert.deepEqual(
    one.outputs.map((o) => o.name),
    ["台本_ト書きあり"],
  );
});

test("行に分ける：BOM と CRLF を取る。最後の改行のあとは行にしない", () => {
  assert.deepEqual(splitLines("﻿a\r\nb\r\n"), ["a", "b"]);
  assert.deepEqual(splitLines("a\n\nb"), ["a", "", "b"]);
  assert.deepEqual(splitLines(""), []);
});

function eq1(got, want) {
  assert.equal(got, want);
}
