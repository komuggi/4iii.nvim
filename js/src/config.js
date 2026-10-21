// 設定：既定値・重ね合わせ・確認（元：daihon の lua/daihon/config.lua）
// 既定値は daihon と同じ。nvim の画面だけで使う設定（keys・show_count・hl など）も、同じ形で受け取れるように残す

export const defaults = {
  mode: "solo", // "solo"（1人・セリフは直打ち）／"multi"（複数人）
  multi: { style: "kagi" }, // "kagi" = 名前「セリフ」／"colon" = 名前：セリフ
  characters: [],

  // 行の種類の表。上から順に見て、最初に当てはまったものになる。どれにも当たらない行＝セリフ
  line_types: [
    { name: "メモ", prefix: ["¥", "￥"], output: false, hl: "DaihonMemo" },
    { name: "指示", prefix: "//", output: true, hl: "DaihonShiji" },
    { name: "位置", prefix: "【", suffix: "】", output: true, hl: "DaihonIchi" },
    { name: "場面", prefix: ["(", "（"], suffix: [")", "）"], output: true, hl: "DaihonBamen" },
  ],

  // 囲い指示。in_types の行の頭に付く。▼ラベル で開いて ▲ラベル で閉じる
  ranges: {
    open: "▼",
    close: "▲",
    in_types: ["指示", "場面"],
    position: ["前", "右前", "左前", "右", "左"],
    distance: ["遠", "中", "近", "密"],
    sep: "・",
    words: [],
    auto_close: true,
    brackets: true, // 行の頭の [[ ]]（「「 」」）を ▼ ▲ にする（このページでは貼り付けのとき）
    guides: true,
  },

  // 見出し。count = true の見出しは、次の同じか上の見出しまでを数える
  headings: [
    { level: 1, prefix: "# " },
    { level: 2, prefix: "## ", count: true, show: "%s : %s文字" },
  ],

  count: {
    include: ["セリフ"],
    ignore_chars: "",
    long_line: 30,
  },

  words: { se: [], shiji: [] },

  // 日本語入力のまま打った記号（／／ ＃ ｛｝ など）を、記号として使う場所でだけ半角にする
  hankaku: true,

  parts_dir: "parts",

  show_count: "winbar",

  keys: {
    toggle: "<localleader>b",
    pick: "<localleader>p",
    hover: "K",
    range_open: "<localleader>[",
    range_close: "<localleader>]",
  },

  export: {
    dir: "out",
    pdf: {
      vertical: true,
      both: true,
      size: "A4 landscape",
      margin: "20mm",
      font: '"BIZ UDPMincho", "BIZ UDP明朝 Medium", "Hiragino Mincho ProN", "Yu Mincho", "Noto Serif JP", serif',
      font_size: "12pt",
      line_height: 1.8,
      page_number: true,
      new_page: 2,
      serifu_indent: "3em",
      vertical_marks: { open: "◀", close: "▶" },
      css: undefined, // 自分の CSS（作品フォルダからの場所）
      command: undefined, // daihon では nvim の設定でだけ変えられる。ここでは使わない
    },
  },
};

const isTable = (t) => t !== null && typeof t === "object";
// Lua の表と同じに見る：中身のある配列だけがリスト。空の [] と {} はどちらも「空の表」
const isList = (t) => Array.isArray(t) && t.length > 0;

function clone(v) {
  if (Array.isArray(v)) return v.map(clone);
  if (isTable(v)) {
    const out = {};
    for (const [k, x] of Object.entries(v)) out[k] = clone(x);
    return out;
  }
  return v;
}

/** base に over を重ねる。表（辞書）は中まで重ね、リストは丸ごと置き換える。null は「書いていない」と同じ */
export function merge(base, over) {
  if (over === undefined || over === null) return clone(base);
  if (!isTable(base) || !isTable(over) || isList(base) || isList(over)) return clone(over);
  const out = clone(base);
  for (const [k, v] of Object.entries(over)) {
    if (v === undefined || v === null) continue;
    out[k] = merge(base[k], v);
  }
  return out;
}

const show = (v) => (v === undefined ? "nil" : JSON.stringify(v));

/** 作品フォルダの中を指す相対の場所か */
export function inside(path) {
  if (typeof path !== "string" || path === "" || /^[/~\\]/.test(path) || /^[A-Za-z]:/.test(path)) return false;
  return !path.split(/[/\\]+/).includes("..");
}

const getPath = (obj, keys) => keys.reduce((o, k) => (isTable(o) ? o[k] : undefined), obj);

/** 設定を確かめる。返す値：{ ok: true } か { ok: false, message } */
export function validate(cfg) {
  const fail = (message) => ({ ok: false, message });
  if (cfg.mode !== "solo" && cfg.mode !== "multi") {
    return fail(`mode は "solo" か "multi" です（今は ${show(cfg.mode)}）`);
  }
  const style = cfg.multi && cfg.multi.style;
  if (style !== "kagi" && style !== "colon") {
    return fail(`multi.style は "kagi" か "colon" です（今は ${show(style)}）`);
  }
  if (!["winbar", "float", "statusline", false].includes(cfg.show_count)) {
    return fail(`show_count は "winbar"・"float"・"statusline"・false のどれかです（今は ${show(cfg.show_count)}）`);
  }
  if (!isTable(cfg.line_types)) return fail("line_types は表で書いてください");
  const lineTypes = Array.isArray(cfg.line_types) ? cfg.line_types : [];
  for (const [i, lt] of lineTypes.entries()) {
    if (typeof lt.name !== "string" || lt.name === "") {
      return fail(`line_types の ${i + 1} 番目に name がありません`);
    }
    if (lt.name === "セリフ") {
      return fail("line_types に「セリフ」は使えません（どれにも当たらない行がセリフです）");
    }
    if (lt.prefix === undefined || lt.prefix === null || lt.prefix === "") {
      return fail(`line_types の「${lt.name}」に prefix がありません`);
    }
  }
  const headings = Array.isArray(cfg.headings) ? cfg.headings : [];
  for (const [i, h] of headings.entries()) {
    if (typeof h.level !== "number" || h.prefix === undefined || h.prefix === null || h.prefix === "") {
      return fail(`headings の ${i + 1} 番目には level と prefix が要ります`);
    }
  }
  for (const key of ["parts_dir", "export.dir", "export.pdf.css"]) {
    const v = getPath(cfg, key.split("."));
    if (v !== undefined && v !== null && !inside(v)) {
      return fail(`${key} は作品フォルダの中の場所にしてください（/ や ~ で始めない・.. を使わない）：${String(v)}`);
    }
  }
  return { ok: true };
}

// 作品ごとの設定では変えられない設定（daihon と同じ）。ここでは PDF のコマンドを設定から受け取らない
export const GLOBAL_ONLY = [["export", "pdf", "command"]];

/** 作品ごとの設定から GLOBAL_ONLY を取り除く。取り除いた名前のリストを返す */
export function stripGlobalOnly(project) {
  const removed = [];
  for (const path of GLOBAL_ONLY) {
    const parent = getPath(project, path.slice(0, -1));
    const last = path[path.length - 1];
    if (isTable(parent) && parent[last] !== undefined && parent[last] !== null) {
      delete parent[last];
      removed.push(path.join("."));
    }
  }
  return removed;
}

/** 既定値に作品ごとの設定を重ねて、確かめる。だめなら Error を投げる */
export function makeConfig(project) {
  const cfg = merge(defaults, project);
  const res = validate(cfg);
  if (!res.ok) throw new Error(res.message);
  return cfg;
}
