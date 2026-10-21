// 元の daihon の tests/test_core.lua・test_ranges.lua のうち、HTML を作るのに使う所を写した物
import { test } from "node:test";
import assert from "node:assert/strict";
import { merge, defaults, validate, inside, stripGlobalOnly } from "../src/config.js";
import { parse, checkRanges, openRangesAt, findRefs } from "../src/parse.js";
import { chars, charSet, format, context, summary, longLines } from "../src/count.js";

const eq = assert.deepEqual;
const cfg = (over) => merge(defaults, over);
const kinds = (records) => records.map((r) => r.kind);
const msgs = (issues) => issues.map((i) => `${i.lnum}:${i.msg}`);

// 設定 ------------------------------------------------------------

test("設定：表は中まで重ね、リストは置き換える", () => {
  const c = cfg({ count: { ignore_chars: "…" }, line_types: [{ name: "指示", prefix: "//" }] });
  eq(c.count.include, ["セリフ"]);
  eq(c.count.ignore_chars, "…");
  eq(c.line_types.length, 1);
});

test("設定：空の [] と {} は Lua の空の表と同じに重ねる", () => {
  eq(cfg({ export: [] }).export.pdf.size, "A4 landscape"); // 辞書に空を重ねても消えない
  eq(cfg({ count: { include: [] } }).count.include, []); // リストは空でも置き換える
  eq(cfg({ export: { pdf: { css: null } } }).export.pdf.css, undefined); // null は書いていないのと同じ
});

test("設定：まちがいを知らせる", () => {
  eq(validate(cfg({ mode: "two" })).ok, false);
  eq(validate(cfg({ mode: "two" })).message, 'mode は "solo" か "multi" です（今は "two"）');
  eq(validate(cfg({ line_types: [{ name: "セリフ", prefix: "!" }] })).ok, false);
  eq(validate(cfg({ line_types: [{ name: "指示" }] })).ok, false);
  eq(validate(cfg()).ok, true);
});

test("安全：PDF のコマンドは作品ごとの設定では変えられない", () => {
  const p = { export: { pdf: { command: ["rm", "-rf", "/"], size: "A5" } } };
  eq(stripGlobalOnly(p), ["export.pdf.command"]);
  eq(p, { export: { pdf: { size: "A5" } } });
});

test("安全：parts と out は作品フォルダの中だけ", () => {
  eq(inside("parts"), true);
  eq(inside("out/pdf"), true);
  for (const bad of ["../x", "/tmp", "~/x", "a/../../b", "C:/x", ""]) eq(inside(bad), false, bad);
  eq(validate(cfg({ parts_dir: "../../.ssh" })).ok, false);
  eq(validate(cfg({ export: { dir: "/tmp" } })).ok, false);
});

// 行の種類 --------------------------------------------------------

test("1人：記号のない行はセリフ", () => {
  const r = parse(
    [
      "# 本編",
      "## Track 01",
      "(放課後の教室)",
      "// SE : 足音",
      "",
      "おかえり",
      "¥ ここもう少し甘く",
      "（全角かっこの場面）",
      "￥ 全角の円記号",
      "【正面・近】",
    ],
    cfg(),
  );
  eq(kinds(r), ["見出し", "見出し", "場面", "指示", "空行", "セリフ", "メモ", "場面", "メモ", "位置"]);
  eq(r[9].body, "正面・近");
  eq(r[1].title, "Track 01");
  eq(r[2].body, "放課後の教室");
  eq(r[3].body, "SE : 足音");
  eq(r[6].output, false);
});

test("複数人：名前「セリフ」と 名前：セリフ", () => {
  let r = parse(["妹「おかえり」", "　姉「遅かったね」"], cfg({ mode: "multi" }));
  eq(r[0].speaker, "妹");
  eq(r[0].body, "おかえり");
  eq(r[1].speaker, "姉");
  eq(r[1].speaker_col, [3, 6]); // バイトで数える（daihon と同じ）

  r = parse(["妹：おかえり", "姉:ただいま"], cfg({ mode: "multi", multi: { style: "colon" } }));
  eq(r[0].speaker, "妹");
  eq(r[0].body, "おかえり");
  eq(r[1].body, "ただいま");
});

test("塊：{{名前 〜 }} と {名前}", () => {
  const r = parse(["{{あいさつ1", "おかえり", "}}", "そして {あいさつ2} も"], cfg());
  eq(kinds(r), ["塊開始", "セリフ", "塊終了", "セリフ"]);
  eq(r[0].block_name, "あいさつ1");
  eq(r[1].in_block, "あいさつ1");
  eq(r[3].refs[0].name, "あいさつ2");
  eq(findRefs("{{あいさつ1").length, 0);
});

test("見出しの記号は設定で変えられる", () => {
  const r = parse(["Track 01", "本文"], cfg({ headings: [{ level: 2, prefix: "Track ", count: true }] }));
  eq(r[0].kind, "見出し");
  eq(r[0].title, "01");
});

// ▼▲ -------------------------------------------------------------

test("▼▲：入れ子で正しく閉じれば何も出ない", () => {
  const r = parse(
    [
      "// ▼前・密",
      "// ▼キスしながら",
      "ちゅっ",
      "// ▲キスしながら",
      "// ▲前・密",
      "(▼呂律が回らない)",
      "(▲呂律が回らない)",
      "//▲無声",
    ],
    cfg(),
  );
  eq(msgs(checkRanges(r, cfg())), ["8:▲無声 に対応する ▼無声 がありません"]);
});

test("▼▲：範囲は重ねてよい（閉じる順番は見ない）", () => {
  const r = parse(["// ▼SE : 水音", "// ▼ささやき", "// ▲SE : 水音", "// ▲ささやき"], cfg());
  eq(msgs(checkRanges(r, cfg())), []);
});

test("▼▲：閉じのラベルは頭だけでもよい。同じラベルを優先する", () => {
  let r = parse(["// ▼口内→ごっくん", "// ▼口", "// ▲口", "// ▲口内"], cfg());
  eq(msgs(checkRanges(r, cfg())), []);
  r = parse(["// ▼前", "// ▲前・中"], cfg());
  eq(checkRanges(r, cfg()).length, 2);
  r = parse(["// ▼前", "// ▲"], cfg());
  eq(checkRanges(r, cfg()).length, 2);
});

test("▼▲：その行の手前で開いているもの", () => {
  const r = parse(["## Track 01", "// ▼左", "## Track 02", "// ▼前・中", "// ▼SE : 足音", "// ▲前・中", ""], cfg());
  eq(
    openRangesAt(r, cfg(), 7).map((o) => o.label),
    ["SE : 足音"],
  );
  eq(openRangesAt(r, cfg(), 6).length, 2);
});

test("▼▲：見出しやファイルの終わりまでに閉じていない", () => {
  const r = parse(["## Track 01", "// ▼前・中", "## Track 02", "// ▼左前"], cfg());
  eq(msgs(checkRanges(r, cfg())), [
    "2:▼前・中 が閉じていません（次の見出しまでに ▲前・中 が要ります）",
    "4:▼左前 が閉じていません（ファイルの終わりまでに ▲左前 が要ります）",
  ]);
});

test("▼▲：記号は設定で変えられる", () => {
  const c = cfg({ ranges: { open: "<<", close: ">>", in_types: ["指示"] } });
  eq(msgs(checkRanges(parse(["// <<前", "// >>前"], c), c)), []);
});

test("▼▲：ラベルの空白の違いは無視する", () => {
  const r = parse(["// ▼SE : 水音", "// ▲SE :水音", "// ▼前　中", "// ▲前中"], cfg());
  eq(msgs(checkRanges(r, cfg())), []);
});

test("範囲：行の頭の ▼▲ は範囲の行。文字数に入れない", () => {
  const c = cfg();
  const r = parse(["▼前・中", "おかえり", "▲前・中", "  ▼右"], c);
  eq(kinds(r), ["範囲", "セリフ", "範囲", "範囲"]);
  eq(r[0].range.label, "前・中");
  eq(r[3].range.col, 2);
  eq(summary(r, context(c)).total, 4);
  eq(msgs(checkRanges(r, c)), ["4:▼右 が閉じていません（ファイルの終わりまでに ▲右 が要ります）"]);
});

// 文字数 ----------------------------------------------------------

test("文字数：空白・全角スペースは数えない。数えない記号を足せる", () => {
  eq(chars("お か　えり"), 4);
  eq(chars("おかえり…。", charSet("…。")), 4);
  eq(format(3369), "3,369");
  eq(format(1234567), "1,234,567");
  eq(format(12), "12");
});

test("文字数：既定はセリフだけ。ト書きも数えられる", () => {
  const c = cfg();
  const r = parse(["## Track 01", "(教室)", "// SE : 足音", "おかえり", "¥ メモは数えない", "ただいま"], c);
  eq(summary(r, context(c)).total, 8);
  eq(summary(r, context(c, undefined, ["セリフ", "指示", "場面"])).total, 15);
});

test("文字数：見出しごと", () => {
  const c = cfg();
  const r = parse(["# 本編", "## Track 01", "あいう", "## Track 02", "かき", "# 特典", "## おまけ", "さ"], c);
  const s = summary(r, context(c));
  eq(s.headings[2], 3);
  eq(s.headings[4], 2);
  eq(s.headings[7], 1);
  eq(s.headings[1], undefined);
});

test("文字数：{名前} は中身で数える。未登録は 0、メモの中は数えない", () => {
  const c = cfg();
  const parts = { あいさつ1: ["おかえり", "// 指示は数えない"], 入れ子: ["{あいさつ1}です"], 自分: ["{自分}"] };
  const ctx = context(c, (name) => parts[name]);
  const r = parse(["{あいさつ1}", "そして{入れ子}", "{ない}", "¥ {あいさつ1}", "{自分}"], c);
  const s = summary(r, ctx);
  eq([s.lines[1], s.lines[2], s.lines[3], s.lines[4], s.lines[5]], [4, 3 + 6, 0, 0, 0]);
  eq(ctx.hasPart("ない"), false);
});

test("文字数：複数人は名前とかっこを数えない", () => {
  const c = cfg({ mode: "multi" });
  eq(summary(parse(["妹「おかえり」"], c), context(c)).total, 4);
});

test("文字数：長いセリフに印。{名前} の字面は数えない。false で付けない", () => {
  const c = cfg();
  const lines = ["あ".repeat(30), "い".repeat(31), "// " + "う".repeat(40), "{" + "え".repeat(40) + "}"];
  const r = parse(lines, c);
  eq(longLines(r, context(c), 30), [{ lnum: 2, n: 31 }]);
  eq(longLines(r, context(c), false), []);
});
