// 元の daihon の tests/test_hankaku.lua を写した物と、貼り付けの直し
import { test } from "node:test";
import assert from "node:assert/strict";
import { convert, brackets, normalizePaste } from "../src/hankaku.js";
import { makeConfig } from "../src/config.js";

const eq = assert.deepEqual;

test("半角：行の頭の ／／ ＃ （ ￥ は半角に", () => {
  eq(convert("／", ""), "/");
  eq(convert("／", "/"), "/");
  eq(convert("／", "  /"), "/");
  eq(convert("＃", ""), "#");
  eq(convert("＃", "#"), "#");
  eq(convert("（", ""), "(");
  eq(convert("）", "(夜"), ")");
  eq(convert("）", "あ（い"), undefined);
  eq(convert("￥", ""), "¥");
});

test("半角：セリフの中の全角はそのまま", () => {
  eq(convert("／", "AかB"), undefined);
  eq(convert("（", "あ"), undefined);
  eq(convert("：", "妹"), undefined);
  eq(convert("：", "// ▼前"), undefined);
  eq(convert("あ", ""), undefined);
});

test("半角：塊のかっこはどこでも、SE のあとの ： と、記号のあとの全角の空白", () => {
  eq(convert("｛", "そして"), "{");
  eq(convert("｝", "{いつもの"), "}");
  eq(convert("：", "// SE"), ":");
  eq(convert("：", "// SE "), ":");
  eq(convert("　", "##"), " ");
  eq(convert("　", "//"), " ");
  eq(convert("　", "おかえり"), undefined);
});

test("半角：行の頭の [[ ]] 「「 」」 は ▼ ▲ に", () => {
  const r = { open: "▼", close: "▲" };
  eq(brackets("[[", r), "▼");
  eq(brackets("]]", r), "▲");
  eq(brackets("「「", r), "▼");
  eq(brackets("  」」", r).trimStart(), "▲");
  eq(brackets("// [[", r), "// ▼");
  eq(brackets("(「「", r), "(▼");
  eq(brackets("あ「「", r), undefined);
  eq(brackets("[", r), undefined);
});

test("貼り付け：1文字ずつ打ったときと同じに直す", () => {
  const cfg = makeConfig({});
  const pasted = "＃＃　Track 01\r\n／／　ＳＥ：足音\r\n（夕方（玄関））\r\n￥ メモ\r\n妹（小声）：｛いつもの｝\r\n「「前・中\r\n// SE：ドア";
  eq(
    normalizePaste(pasted, cfg),
    "## Track 01\n// ＳＥ：足音\n(夕方（玄関))\n¥ メモ\n妹（小声）：{いつもの}\n▼前・中\n// SE:ドア",
  );
});

test("貼り付け：行の途中に貼るときは、前の文字を見て直す。設定で止められる", () => {
  const cfg = makeConfig({});
  eq(normalizePaste("／ あ", cfg, "/"), "/ あ");
  eq(normalizePaste("／ あ", cfg, "あ"), "／ あ");
  eq(normalizePaste("[", cfg, "["), "["); // 貼る所より前の文字は変えない
  eq(normalizePaste("／／　あ\n[[前", makeConfig({ hankaku: false, ranges: { brackets: false } })), "／／　あ\n[[前");
});
