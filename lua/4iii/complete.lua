-- 候補を決める。ファイルや画面には触らない
local parse = require("4iii.parse")

local M = {}

local function push(items, seen, word, menu)
  if word ~= "" and not seen[word] then
    seen[word] = true
    items[#items + 1] = { word = word, menu = menu }
  end
end

--- ▼ のあとに出すラベル：この台本で使ったもの（多い順）→ 位置×距離 → そのほかの言葉
function M.open_labels(records, cfg)
  local r = cfg.ranges or {}
  local used, order = {}, {}
  for _, rec in ipairs(records) do
    local label = rec.range and rec.range.op == "open" and rec.range.label
    if label and label ~= "" then
      if not used[label] then
        order[#order + 1] = label
      end
      used[label] = (used[label] or 0) + 1
    end
  end
  table.sort(order, function(a, b)
    return used[a] > used[b]
  end)

  local items, seen = {}, {}
  for _, label in ipairs(order) do
    push(items, seen, label, "使った")
  end
  local sep = r.sep or "・"
  for _, p in ipairs(r.position or {}) do
    for _, d in ipairs(r.distance or {}) do
      push(items, seen, p .. sep .. d, "位置")
    end
  end
  for _, w in ipairs(r.words or {}) do
    push(items, seen, w, "言葉")
  end
  return items
end

--- ▲ のあとに出すラベル：まだ閉じていない ▼（新しく開いた順）
local function close_labels(records, cfg)
  local items = {}
  local open = parse.open_ranges_at(records, cfg, #records + 1)
  for k = #open, 1, -1 do
    items[#items + 1] = { word = open[k].label, menu = ("%d行目"):format(open[k].lnum) }
  end
  return items
end

--- 指示の中身が「SE : …」「SE：…」なら、そのあとの文字。違えば nil
--- （全角の「：」は3バイトなので、[:：] のようにまとめて書けない）
local function se_rest(body)
  return body:match("^SE%s*:%s*(.-)$") or body:match("^SE%s*：%s*(.-)$")
end

--- 「・」「、」で区切った最後の1つ
local function last_part(s)
  local cut = 0
  for _, sep in ipairs({ "・", "、" }) do
    local i = 0
    while true do
      local j = s:find(sep, i + 1, true)
      if not j then
        break
      end
      i = j
      cut = math.max(cut, j + #sep - 1)
    end
  end
  return s:sub(cut + 1)
end

--- 言葉の数を数えて、多い順に並べる
local function by_count(list)
  local n, order = {}, {}
  for _, w in ipairs(list) do
    if w ~= "" then
      if not n[w] then
        order[#order + 1] = w
      end
      n[w] = (n[w] or 0) + 1
    end
  end
  table.sort(order, function(a, b)
    return n[a] > n[b]
  end)
  return order
end

--- SE のあとに出す言葉：登録したもの → この台本で使ったもの（多い順）
function M.se_words(records, cfg)
  local used = {}
  for _, rec in ipairs(records) do
    local rest = rec.kind == "指示" and not rec.range and se_rest(rec.body)
    if rest then
      for part in (rest .. "・"):gmatch("(.-)・") do
        for w in (part .. "、"):gmatch("(.-)、") do
          used[#used + 1] = parse.trim(w)
        end
      end
    end
  end
  local items, seen = {}, {}
  for _, w in ipairs((cfg.words or {}).se or {}) do
    push(items, seen, w, "登録")
  end
  for _, w in ipairs(by_count(used)) do
    push(items, seen, w, "使った")
  end
  return items
end

--- 指示の言葉：登録したもの → この台本で使った指示（SE と ▼▲ を除く、多い順）
function M.shiji_words(records, cfg)
  local used = {}
  for _, rec in ipairs(records) do
    if rec.kind == "指示" and not rec.range and not se_rest(rec.body) then
      used[#used + 1] = rec.body
    end
  end
  local items, seen = {}, {}
  for _, w in ipairs((cfg.words or {}).shiji or {}) do
    push(items, seen, w, "登録")
  end
  for _, w in ipairs(by_count(used)) do
    push(items, seen, w, "使った")
  end
  return items
end

--- カーソルより前の文字（before）から、候補を出す場所と候補を決める
--- above はその行より上の台本（閉じていない ▼ を拾う）。all は台本全体（使った言葉を拾う。なければ above）
--- 返す表：{ col = 置き換えを始める位置（0 始まり）, items, auto = 打った直後に出すか }。出さないなら nil
function M.at(before, above, cfg, all)
  all = all or above
  local rec = parse.parse({ before }, cfg)[1]
  if not rec then
    return nil
  end
  if rec.range then
    local label = rec.range.label
    local items = rec.range.op == "open" and M.open_labels(all, cfg) or close_labels(above, cfg)
    return { col = #before - #label, items = items, auto = label == "" }
  end
  if rec.kind ~= "指示" then
    return nil
  end
  local rest = se_rest(rec.body)
  if rest then
    -- SE : のあと（「・」「、」で区切った次も）は、打った直後に出す
    local part = last_part(rest)
    return { col = #before - #part, items = M.se_words(all, cfg), auto = part == "" }
  end
  -- ほかの指示は <C-x><C-o> のときだけ
  return { col = #before - #rec.body, items = M.shiji_words(all, cfg), auto = false }
end

--- 打った分（base）で絞る
function M.filter(items, base)
  if base == "" then
    return items
  end
  return vim.tbl_filter(function(it)
    return vim.startswith(it.word, base)
  end, items)
end

return M
