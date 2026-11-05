-- 文字数を数える。ファイルや画面には触らない（塊の中身は get_part で外から受け取る）
local parse = require("4iii.parse")

local M = {}

local CHAR = "[%z\1-\127\194-\244][\128-\191]*" -- UTF-8 の1文字
local ZEN_SPACE = "\227\128\128"
local MAX_DEPTH = 10 -- 塊の中の塊をたどる深さの上限（ループよけ）

function M.char_set(s)
  local set = {}
  for ch in (s or ""):gmatch(CHAR) do
    set[ch] = true
  end
  return set
end

--- 空白・改行と ignore の記号を除いた文字数
function M.chars(s, ignore)
  local n = 0
  for ch in s:gmatch(CHAR) do
    if not (ch:match("^%s$") or ch == ZEN_SPACE or (ignore and ignore[ch])) then
      n = n + 1
    end
  end
  return n
end

--- 3369 → "3,369"
function M.format(n)
  local s = tostring(n)
  while true do
    local t, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
    s = t
    if k == 0 then
      return s
    end
  end
end

--- 数えるための道具をまとめる
--- get_part(name) は塊の中身の行（リスト）を返す。なければ nil
--- include を渡すと cfg.count.include の代わりに使う
function M.context(cfg, get_part, include)
  local ctx = {
    cfg = cfg,
    include = {},
    ignore = M.char_set(cfg.count and cfg.count.ignore_chars),
    _lines = {},
    _counts = {},
  }
  for _, k in ipairs(include or (cfg.count and cfg.count.include) or { "セリフ" }) do
    ctx.include[k] = true
  end

  function ctx.part_lines(name)
    if ctx._lines[name] == nil then
      ctx._lines[name] = (get_part and get_part(name)) or false
    end
    return ctx._lines[name] or nil
  end

  function ctx.has_part(name)
    return ctx.part_lines(name) ~= nil
  end

  function ctx.part_count(name, depth)
    depth = depth or 0
    if ctx._counts[name] ~= nil then
      return ctx._counts[name]
    end
    local lines = ctx.part_lines(name)
    if not lines or depth > MAX_DEPTH then
      return 0
    end
    ctx._counts[name] = 0 -- 自分自身を呼ぶ塊よけ
    local n = 0
    for _, r in ipairs(parse.parse(lines, cfg)) do
      n = n + M.line(r, ctx, depth + 1)
    end
    ctx._counts[name] = n
    return n
  end

  return ctx
end

--- 1行の文字数。{名前} は字面ではなく塊の中身で数える。出力しない行は 0
function M.line(r, ctx, depth)
  if not r.output then
    return 0
  end
  local n = 0
  if ctx.include[r.kind] and r.body then
    n = M.chars((r.body:gsub("{[^{}]+}", "")), ctx.ignore)
  end
  for _, ref in ipairs(r.refs or {}) do
    n = n + ctx.part_count(ref.name, depth)
  end
  return n
end

--- limit 文字より長いセリフの行。返す表：{ { lnum, n }, ... }（{名前} の字面は数えない）
function M.long_lines(records, ctx, limit)
  local out = {}
  if not limit then
    return out
  end
  for _, r in ipairs(records) do
    if r.kind == "セリフ" and r.body then
      local n = M.chars((r.body:gsub("{[^{}]+}", "")), ctx.ignore)
      if n > limit then
        out[#out + 1] = { lnum = r.lnum, n = n }
      end
    end
  end
  return out
end

--- lnum 行目が入っている「数える見出し」（トラック）の行。外なら nil
function M.current(records, summary, lnum)
  for i = math.min(lnum, #records), 1, -1 do
    local r = records[i]
    if r.kind == "見出し" then
      return summary.headings[r.lnum] and r or nil
    end
  end
end

--- 常に出す文字数の文：「Track 01 おかえり 32文字 ／ 全体 41文字」
function M.bar_text(records, summary, lnum)
  local total = "全体 " .. M.format(summary.total) .. "文字"
  local h = M.current(records, summary, lnum)
  if not h then
    return total
  end
  return ("%s %s文字 ／ %s"):format(h.title, M.format(summary.headings[h.lnum]), total)
end

--- 全体と見出しごとの文字数
--- 返す表：{ total, lines = { [lnum] = n }, headings = { [lnum] = n } }
function M.summary(records, ctx)
  local per = {}
  local total = 0
  for _, r in ipairs(records) do
    local n = M.line(r, ctx, 0)
    per[r.lnum] = n
    total = total + n
  end

  local headings = {}
  for i, r in ipairs(records) do
    if r.kind == "見出し" and r.heading.count then
      local n = 0
      for j = i + 1, #records do
        local q = records[j]
        if q.kind == "見出し" and q.level <= r.level then
          break
        end
        n = n + per[q.lnum]
      end
      headings[r.lnum] = n
    end
  end
  return { total = total, lines = per, headings = headings }
end

return M
