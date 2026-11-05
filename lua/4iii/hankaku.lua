-- 日本語入力のまま打った記号を、記号として使う場所でだけ半角にする。ファイルや画面には触らない
local M = {}

local ZEN_SPACE = "\227\128\128" -- 全角スペース（U+3000）

-- 打った字 → { 半角, 半角にする場所（カーソルより前の文字がこの形のとき） }
local RULES = {
  ["／"] = { "/", { "^%s*$", "^%s*/$" } }, -- 行の頭の //
  ["＃"] = { "#", { "^%s*#*$" } }, -- 見出しの #
  ["（"] = { "(", { "^%s*$" } }, -- 場面
  ["）"] = { ")", { "^%s*%(" } }, -- 場面の閉じ（行が ( で始まるときだけ）
  ["￥"] = { "¥", { "^%s*$" } }, -- メモ
  ["｛"] = { "{", { "" } }, -- 塊はどこでも
  ["｝"] = { "}", { "" } },
  ["："] = { ":", { "^%s*//%s*SE%s*$" } }, -- // SE :
  [ZEN_SPACE] = { " ", { "^%s*#+$", "^%s*//$" } }, -- # や // のすぐあとの空白
}

--- 打った字（ch）を半角にするなら、その半角を返す。しないなら nil
--- before はカーソルより前の、同じ行の文字
function M.convert(ch, before)
  local rule = RULES[ch]
  if not rule then
    return nil
  end
  for _, pat in ipairs(rule[2]) do
    if before:find(pat) then
      return rule[1]
    end
  end
end

--- 行の頭（「// 」「(」のあとも）の [[ ]] 「「 」」 を ▼ ▲ にした「カーソルより前」を返す。変えないなら nil
function M.brackets(before, ranges)
  local open, close = ranges.open or "▼", ranges.close or "▲"
  local pairs_ = { { "%[%[", open }, { "「「", open }, { "%]%]", close }, { "」」", close } }
  for _, head in ipairs({ "^(%s*)", "^(%s*//%s*)", "^(%s*%(%s*)" }) do
    for _, p in ipairs(pairs_) do
      local lead = before:match(head .. p[1] .. "$")
      if lead then
        return lead .. p[2]
      end
    end
  end
end

return M
