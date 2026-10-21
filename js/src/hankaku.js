// 日本語入力のまま打った記号を、記号として使う場所でだけ半角にする（元：daihon の lua/daihon/hankaku.lua）
// daihon は1文字打つごとに直す。ここでは貼り付けた文を1文字ずつ「打った」とみなして、同じ決まりで直す

const S = "[ \\t\\n\\v\\f\\r]"; // Lua の %s
const re = (src) => new RegExp(src.replaceAll("%s", S));

// 打った字 → [半角, 半角にする場所（カーソルより前の文字がこの形のとき）]
const RULES = {
  "／": ["/", [re("^%s*$"), re("^%s*/$")]], // 行の頭の //
  "＃": ["#", [re("^%s*#*$")]], // 見出しの #
  "（": ["(", [re("^%s*$")]], // 場面
  "）": [")", [re("^%s*\\(")]], // 場面の閉じ（行が ( で始まるときだけ）
  "￥": ["¥", [re("^%s*$")]], // メモ
  "｛": ["{", [/(?:)/]], // 塊はどこでも
  "｝": ["}", [/(?:)/]],
  "：": [":", [re("^%s*//%s*SE%s*$")]], // // SE :
  "　": [" ", [re("^%s*#+$"), re("^%s*//$")]], // # や // のすぐあとの空白
};

/** 打った字（ch）を半角にするなら、その半角を返す。しないなら undefined。before はカーソルより前の、同じ行の文字 */
export function convert(ch, before) {
  const rule = RULES[ch];
  if (!rule) return undefined;
  return rule[1].some((p) => p.test(before)) ? rule[0] : undefined;
}

const escapeRe = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

/** 行の頭（「// 」「(」のあとも）の [[ ]] 「「 」」 を ▼ ▲ にした「カーソルより前」を返す。変えないなら undefined */
export function brackets(before, ranges) {
  const open = ranges.open || "▼";
  const close = ranges.close || "▲";
  const pairs = [
    ["\\[\\[", open],
    ["「「", open],
    ["\\]\\]", close],
    ["」」", close],
  ];
  for (const head of [`^(${S}*)`, `^(${S}*//${S}*)`, `^(${S}*\\(${S}*)`]) {
    for (const [mark, to] of pairs) {
      const m = before.match(new RegExp(head + mark + "$"));
      if (m) return m[1] + to;
    }
  }
  return undefined;
}

/**
 * 貼り付けた文を、daihon で1文字ずつ打ったときと同じ形にする
 * before：貼り付ける所より前の、同じ行の文字（行の途中に貼るとき）
 * cfg.hankaku が false なら記号は直さない。cfg.ranges.brackets が false なら [[ ]] は直さない
 */
export function normalizePaste(text, cfg, before = "") {
  const lines = text.replace(/\r\n?/g, "\n").split("\n");
  const useHankaku = cfg.hankaku !== false;
  const useBrackets = !!(cfg.ranges && cfg.ranges.brackets);
  return lines
    .map((line, i) => {
      const lead = i === 0 ? before : "";
      let typed = lead;
      for (const ch of line) {
        typed += (useHankaku && convert(ch, typed)) || ch;
        const b = useBrackets ? brackets(typed, cfg.ranges) : undefined;
        if (b !== undefined && b.startsWith(lead)) typed = b; // 貼る所より前の文字は変えない
      }
      return typed.slice(lead.length);
    })
    .join("\n");
}
