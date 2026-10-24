// ルビと、ページの枠（daihon には無い・js 版だけ）
import { test } from "node:test";
import assert from "node:assert/strict";
import { makeConfig, render, fields } from "../src/index.js";
import { split, plain } from "../src/ruby.js";
import { defaults } from "../src/config.js";

const eq = assert.deepEqual;
const R = defaults.ruby;

test("ルビ：| から 《 まで・| が無いときは前に続く漢字・pixiv の形", () => {
  eq(split("|お姉様《ねえさま》の声", R), [{ base: "お姉様", reading: "ねえさま" }, { text: "の声" }]);
  eq(split("それは囁《ささや》き", R), [{ text: "それは" }, { base: "囁", reading: "ささや" }, { text: "き" }]);
  eq(split("今日は月曜日《げつようび》", R), [{ text: "今日は" }, { base: "月曜日", reading: "げつようび" }]);
  eq(split("[[rb:耳元 > みみもと]]で", R), [{ base: "耳元", reading: "みみもと" }, { text: "で" }]);
  eq(split("｜ＡＳＭＲ《えーえすえむあーる》", R), [{ base: "ＡＳＭＲ", reading: "えーえすえむあーる" }]);
});

test("ルビ：当たらない物はそのまま・ruby = false で読まない", () => {
  eq(split("かな《かな》", R), [{ text: "かな《かな》" }]); // 漢字が無く | も無い
  eq(split("《》だけ", R), [{ text: "《》だけ" }]);
  eq(split("漢字《かんじ》", false), [{ text: "漢字《かんじ》" }]);
  eq(split("[[rb:耳元 > みみもと]]", { ...R, pixiv: false }), [{ text: "[[rb:耳元 > みみもと]]" }]);
});

test("ルビ：記号を自分の形にできる", () => {
  const mine = { start: ["#"], open: "（", close: "）", pixiv: false };
  eq(split("#お兄ちゃん（にいに）", mine), [{ base: "お兄ちゃん", reading: "にいに" }]);
  eq(plain("兄（にい）さん", mine), "兄さん");
});

test("ルビ：HTML は縦書きでも横書きでも ruby にし、読みは文字数に入れない", () => {
  const text = "## Track 01\n|お姉様《ねえさま》、おかえり";
  const v = render(text, makeConfig({}));
  assert.match(v.outputs[0].html, /<ruby>お姉様<rt>ねえさま<\/rt><\/ruby>、おかえり/);
  eq(v.summary.total, 8); // お姉様、おかえり
  const h = render(text, makeConfig({ export: { pdf: { vertical: false } } }));
  assert.match(h.outputs[0].html, /<ruby>お姉様<rt>ねえさま<\/rt><\/ruby>/);
  assert.doesNotMatch(h.outputs[0].html, /vertical-rl/);
});

test("ルビ：読みの中の < は文字のまま", () => {
  const out = render("|A《<b>》", makeConfig({})).outputs[0].html;
  assert.match(out, /<ruby>A<rt>&lt;b&gt;<\/rt><\/ruby>/);
});

test("ルビ：ruby は表か false", () => {
  assert.throws(() => makeConfig({ ruby: true }), /ruby は表か false/);
  eq(makeConfig({ ruby: false }).ruby, false);
});

// ページの枠 ------------------------------------------------------

test("枠：開いたときの記号で、SE・演技指示・その他・セリフに分かれる", () => {
  const text = ["SE：ドアが開く", "// SE : 足音", "（夕方の玄関）", "【右・近】", "¥ メモ", "おかえりなさい"].join("\n");
  const res = render(text, makeConfig(fields.START));
  eq(
    res.records.map((r) => r.kind),
    ["SE", "SE", "指示", "指示", "メモ", "セリフ"],
  );
  eq(res.summary.total, 7);
  const [withT, withoutT] = res.outputs;
  assert.match(withT.html, /class="t-指示">SE：ドアが開く/);
  assert.doesNotMatch(withT.html, /メモ/);
  assert.doesNotMatch(withoutT.html, /ドアが開く|夕方/);
});

test("枠：読む・書くで元に戻る。その他を出す・空の枠は使わない・足した種類は残す", () => {
  const f = fields.read(fields.START);
  eq([f.se, f.shiji, f.other, f.otherOutput, f.vertical], ["// SE、SE：、SE:", "//、(、（、【", "¥、￥", false, true]);
  eq(fields.write(fields.START, f).line_types, fields.START.line_types);

  const p = fields.write({ line_types: [...fields.START.line_types, { name: "注意", prefix: "※" }] }, {
    ...f,
    se: "",
    other: "#、＃ ",
    otherOutput: true,
  });
  eq(
    p.line_types.map((t) => [t.name, t.prefix, t.output]),
    [
      ["指示", ["//", "(", "（", "【"], undefined],
      ["メモ", ["#", "＃"], true],
      ["注意", "※", undefined],
    ],
  );
  eq(fields.read(p).extra, ["注意"]);
});

test("枠：横書きは紙を A4 縦にし、縦書きに戻すと元に戻す。自分で書いた紙は変えない", () => {
  const f = fields.read(fields.START);
  const h = fields.write(fields.START, { ...f, vertical: false });
  eq(h.export.pdf, { vertical: false, size: "A4 portrait" });
  eq(fields.write(h, { ...f, vertical: true }).export.pdf, { vertical: true });
  const b5 = fields.write({ export: { pdf: { size: "B5" } } }, { ...f, vertical: false });
  eq(b5.export.pdf.size, "B5");
});

test("枠：ルビを切る・自分の記号にする", () => {
  const f = fields.read(fields.START);
  eq(f.ruby, { on: true, start: "|、｜", open: "《", close: "》", pixiv: true });
  eq(fields.write(fields.START, { ...f, ruby: { ...f.ruby, on: false } }).ruby, false);
  eq(fields.write(fields.START, { ...f, ruby: { on: true, start: "#", open: "（", close: "）", pixiv: false } }).ruby, {
    start: ["#"],
    open: "（",
    close: "）",
    pixiv: false,
  });
});
