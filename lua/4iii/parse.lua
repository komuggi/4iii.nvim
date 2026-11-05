-- 台本の行を種類に分ける。ファイルや画面には触らない
local M = {}

local ZEN_SPACE = "\227\128\128" -- 全角スペース（U+3000）

local function as_list(x)
  if x == nil then
    return {}
  end
  if type(x) == "table" then
    return x
  end
  return { x }
end

--- 前後の空白（全角スペースを含む）を取る
function M.trim(s)
  while true do
    local t = s:gsub("^%s+", ""):gsub("%s+$", "")
    if t:sub(1, 3) == ZEN_SPACE then
      t = t:sub(4)
    end
    if t:sub(-3) == ZEN_SPACE then
      t = t:sub(1, -4)
    end
    if t == s then
      return t
    end
    s = t
  end
end

local function match_prefix(s, prefixes)
  for _, p in ipairs(as_list(prefixes)) do
    if p ~= "" and s:sub(1, #p) == p then
      return p
    end
  end
end

local function strip_suffix(s, suffixes)
  for _, p in ipairs(as_list(suffixes)) do
    if p ~= "" and #s >= #p and s:sub(-#p) == p then
      return s:sub(1, -#p - 1)
    end
  end
  return s
end

--- 行の中の {名前} を探す。s, e は行の中のバイト位置（1 始まり）
function M.find_refs(line)
  local refs = {}
  local init = 1
  while true do
    local s, e, name = line:find("{([^{}]+)}", init)
    if not s then
      break
    end
    local before = s > 1 and line:sub(s - 1, s - 1) or ""
    local after = line:sub(e + 1, e + 1)
    if before ~= "{" and after ~= "}" then
      refs[#refs + 1] = { name = M.trim(name), s = s, e = e }
    end
    init = e + 1
  end
  return refs
end

--- 複数人のセリフから名前と中身を分ける。名前がなければ nil
local function split_speaker(text, style)
  local marks = style == "colon" and { "：", ":" } or { "「" }
  for _, mark in ipairs(marks) do
    local s, e = text:find(mark, 1, true)
    if s and s > 1 then
      local name = M.trim(text:sub(1, s - 1))
      local body = text:sub(e + 1)
      if style == "kagi" then
        body = strip_suffix(M.trim(body), "」")
      end
      if name ~= "" then
        return name, M.trim(body), s - 1
      end
    end
  end
end

--- ▼▲ のラベルを比べるための形（空白の違いは無視する）
function M.label_key(label)
  return (label:gsub("%s", ""):gsub(ZEN_SPACE, ""))
end

local function find_range(body, ranges)
  for _, op in ipairs({ "open", "close" }) do
    local mark = ranges[op]
    if mark and mark ~= "" and body:sub(1, #mark) == mark then
      local label = M.trim(body:sub(#mark + 1))
      return { op = op, mark = mark, label = label, key = M.label_key(label) }
    end
  end
end

--- 行を1つずつ種類に分ける
--- 返す表：{ lnum, text, kind, body, output, ... }
---   kind = "空行" | "見出し" | "塊開始" | "塊終了" | "セリフ" | line_types の name
function M.parse(lines, cfg)
  local records = {}
  local ranges = cfg.ranges or {}
  local range_types = {}
  for _, n in ipairs(ranges.in_types or {}) do
    range_types[n] = true
  end

  local in_block = nil
  for i, line in ipairs(lines) do
    local r = { lnum = i, text = line }
    local t = M.trim(line)
    local lead = t == "" and 0 or (line:find(t, 1, true) - 1)

    if t == "" then
      r.kind = "空行"
    elseif t:sub(1, 2) == "{{" then
      r.kind = "塊開始"
      r.block_name = M.trim(t:sub(3))
      in_block = r.block_name
    elseif t == "}}" and in_block then
      r.kind = "塊終了"
      r.block_name = in_block
      in_block = nil
    else
      r.in_block = in_block
      for _, h in ipairs(cfg.headings or {}) do
        local p = match_prefix(t, h.prefix)
        if p then
          r.kind = "見出し"
          r.heading = h
          r.level = h.level
          r.title = M.trim(t:sub(#p + 1))
          break
        end
      end
      if not r.kind then
        -- 行の頭に ▼▲ を直接書いた行は、範囲だけの行
        local rg = find_range(t, ranges)
        if rg then
          r.kind = "範囲"
          r.output = true
          r.body = t
          r.range = rg
          r.range.col = lead
        end
      end
      if not r.kind then
        for _, lt in ipairs(cfg.line_types or {}) do
          local p = match_prefix(t, lt.prefix)
          if p then
            r.kind = lt.name
            r.type = lt
            r.output = lt.output ~= false
            r.body = M.trim(strip_suffix(M.trim(t:sub(#p + 1)), lt.suffix))
            if range_types[lt.name] then
              r.range = find_range(r.body, ranges)
              if r.range then
                r.range.col = line:find(r.range.mark, lead + 1, true) - 1
              end
            end
            break
          end
        end
      end
      if not r.kind then
        r.kind = "セリフ"
        r.output = true
        r.body = t
        if cfg.mode == "multi" then
          local name, body, name_len = split_speaker(t, cfg.multi and cfg.multi.style)
          if name then
            r.speaker = name
            r.speaker_col = { lead, lead + name_len }
            r.body = body
          end
        end
      end
      r.refs = M.find_refs(line)
    end
    records[#records + 1] = r
  end
  return records
end

--- 閉じのラベルに当たる「開いている ▼」を探す（何番目か）
--- 同じラベルを優先し、なければ頭が同じもの。どちらも新しく開いた方から探す
function M.find_open(open, key)
  for k = #open, 1, -1 do
    if open[k].key == key then
      return k
    end
  end
  if key == "" then
    return nil
  end
  for k = #open, 1, -1 do
    if open[k].key:sub(1, #key) == key then
      return k
    end
  end
end

--- ▼▲ を上からたどる。範囲は重ねてよい（閉じる順番は見ない）
--- stop を渡すと、その行の手前で開いているものを返す。issues を渡すと警告を足す
local function walk_ranges(records, cfg, stop, issues)
  local ranges = cfg.ranges or {}
  local open_m, close_m = ranges.open or "", ranges.close or ""
  local open = {}

  local function flush(where)
    if issues then
      for _, o in ipairs(open) do
        issues[#issues + 1] = {
          lnum = o.lnum,
          col = o.col,
          msg = ("%s%s が閉じていません（%sまでに %s%s が要ります）"):format(
            open_m,
            o.label,
            where,
            close_m,
            o.label
          ),
        }
      end
    end
    open = {}
  end

  for _, r in ipairs(records) do
    if stop and r.lnum >= stop then
      return open
    end
    if r.kind == "見出し" then
      flush("次の見出し")
    elseif r.range and r.range.op == "open" then
      open[#open + 1] = { label = r.range.label, key = r.range.key, lnum = r.lnum, col = r.range.col }
    elseif r.range and r.range.op == "close" then
      local k = M.find_open(open, r.range.key)
      if k then
        table.remove(open, k)
      elseif issues then
        issues[#issues + 1] = {
          lnum = r.lnum,
          col = r.range.col,
          msg = ("%s%s に対応する %s%s がありません"):format(close_m, r.range.label, open_m, r.range.label),
        }
      end
    end
  end
  if not stop then
    flush("ファイルの終わり")
  end
  return open
end

--- 行ごとに、その行を囲んでいる範囲（開いた順）。縦の線に使う
--- ▼ の行は自分を含まず、▲ の行は自分が閉じた後の形。返す表：{ [lnum] = { { label, key, lnum }, ... } }
function M.range_depths(records, cfg)
  local out, open = {}, {}
  local function snap(lnum)
    if #open > 0 then
      out[lnum] = vim.list_slice(open)
    end
  end
  for _, r in ipairs(records) do
    if r.kind == "見出し" then
      open = {}
    elseif r.range and r.range.op == "close" then
      local k = M.find_open(open, r.range.key)
      if k then
        table.remove(open, k)
      end
      snap(r.lnum)
    else
      snap(r.lnum)
      if r.range and r.range.op == "open" then
        open[#open + 1] = { label = r.range.label, key = r.range.key, lnum = r.lnum }
      end
    end
  end
  return out
end

--- ▼ の行から、対になる ▲ の行の文字を作る（「// ▼前」→「// ▲前」、「(▼前)」→「(▲前)」）
function M.close_text(r, cfg)
  local close = (cfg.ranges or {}).close or "▲"
  local i = r.range.col + 1
  return r.text:sub(1, i - 1) .. close .. r.text:sub(i + #r.range.mark)
end

--- below（▼ の行より下）に、この ▼ を閉じる ▲ があるか（次の見出しまで）
function M.has_close_below(below, key)
  for _, r in ipairs(below) do
    if r.kind == "見出し" then
      return false
    end
    if r.range and r.range.op == "close" and r.range.key ~= "" and key:sub(1, #r.range.key) == r.range.key then
      return true
    end
    if r.range and r.range.op == "open" and r.range.key == key then
      return false -- 閉じる前に、同じラベルがまた開いている
    end
  end
  return false
end

--- ▼▲ の対応を確かめる。返す表：{ { lnum, col, msg }, ... }
function M.check_ranges(records, cfg)
  local issues = {}
  walk_ranges(records, cfg, nil, issues)
  return issues
end

--- lnum 行目の手前で開いている ▼ の一覧（開いた順）。▲ の候補に使う
function M.open_ranges_at(records, cfg, lnum)
  return walk_ranges(records, cfg, lnum)
end

return M
