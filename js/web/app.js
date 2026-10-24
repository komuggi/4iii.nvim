// ブラウザのページ：貼った台本 → 縦書きのプレビュー → 印刷して PDF に
// 部品（../src/index.js）をそのまま使う。外の CDN は使わない
// 台本はどこにも送らず、ブラウザにも残さない（外への通信は index.html の CSP で止めている）
import { makeConfig, render, splitLines, validPartName, parser, hankaku, config as configLib } from "../src/index.js";

const $ = (id) => document.getElementById(id);
const textBox = $("text");
const configBox = $("config");
const nameBox = $("name");
const frame = $("preview");
const status = $("status");
const parts = new Map(); // 名前 → 行の配列

// 画面で見るときだけの見た目（印刷には効かない）
const SCREEN_CSS = "@media screen { html { background: #fff; } body { padding: 24px; } }";

let cfg = makeConfig({});

function readConfig() {
  const error = $("config-error");
  try {
    const project = JSON.parse(configBox.value.trim() || "{}");
    configLib.stripGlobalOnly(project);
    cfg = makeConfig(project);
    error.textContent = "";
  } catch (err) {
    error.textContent = `設定を読めません（前の設定のまま）：${err.message}`;
  }
}

function update() {
  const togaki = document.querySelector('input[name="togaki"]:checked').value === "1";
  const lines = splitLines(textBox.value);
  const res = render(lines, cfg, { name: nameBox.value.trim() || "台本", getPart: (n) => parts.get(n) });
  const out = res.outputs.find((o) => o.togaki === togaki) || res.outputs[0];
  const html = out.html.replace("</style>", `${SCREEN_CSS}\n</style>`);
  // スクロールの位置を残して差し替える
  const win = frame.contentWindow;
  const scroll = win ? [win.scrollX, win.scrollY] : [0, 0];
  frame.onload = () => frame.contentWindow.scrollTo(...scroll);
  frame.srcdoc = html;
  document.title = `${out.name} - 縦書き台本`;

  const notes = [`全体 ${res.summary.total.toLocaleString()}文字`];
  if (!togaki && !cfg.export.pdf.both) notes.push("（設定の export.pdf.both が false なので、ト書きありだけ）");
  const warns = [];
  if (res.missing.length > 0) warns.push(`未登録の塊：${res.missing.join("、")}`);
  for (const issue of parser.checkRanges(res.records, cfg)) warns.push(`${issue.lnum}行目 ${issue.msg}`);
  status.replaceChildren(notes.join(" "));
  for (const w of warns.slice(0, 5)) {
    const span = document.createElement("span");
    span.className = "warn";
    span.textContent = ` ／ ${w}`;
    status.append(span);
  }
  if (warns.length > 5) status.append(` ほか ${warns.length - 5}件`);
}

let timer;
function schedule() {
  clearTimeout(timer);
  timer = setTimeout(update, 150);
}

// 貼り付け：日本語入力のままの記号（／／ ＃ ｛｝ など）を、daihon で打ったときと同じに直す
textBox.addEventListener("paste", (ev) => {
  const pasted = ev.clipboardData && ev.clipboardData.getData("text/plain");
  if (!pasted) return;
  ev.preventDefault();
  const start = textBox.selectionStart;
  const lineStart = textBox.value.lastIndexOf("\n", start - 1) + 1;
  const before = textBox.value.slice(lineStart, start);
  const fixed = hankaku.normalizePaste(pasted, cfg, before);
  textBox.setRangeText(fixed, start, textBox.selectionEnd, "end");
  schedule();
});

textBox.addEventListener("input", schedule);
nameBox.addEventListener("input", schedule);
configBox.addEventListener("input", () => {
  readConfig();
  schedule();
});
for (const radio of document.querySelectorAll('input[name="togaki"]')) radio.addEventListener("change", update);

$("parts").addEventListener("change", async (ev) => {
  for (const file of ev.target.files) {
    const name = file.name.replace(/\.txt$/i, "");
    if (validPartName(name)) parts.set(name, splitLines(await file.text()));
  }
  $("parts-list").textContent = parts.size > 0 ? `読んだ塊：${[...parts.keys()].join("、")}` : "塊はまだありません";
  update();
});

function printPreview() {
  const win = frame.contentWindow;
  if (!win) return;
  win.focus();
  win.print();
}
$("print").addEventListener("click", printPreview);
// ⌘P / Ctrl+P でも、ページではなくプレビューを印刷する
window.addEventListener("keydown", (ev) => {
  if ((ev.metaKey || ev.ctrlKey) && ev.key.toLowerCase() === "p") {
    ev.preventDefault();
    printPreview();
  }
});

// 台本はブラウザにも残さない。閉じる・読み直す前に確かめる
window.addEventListener("beforeunload", (ev) => {
  if (textBox.value.trim() !== "") ev.preventDefault();
});

readConfig();
update();
