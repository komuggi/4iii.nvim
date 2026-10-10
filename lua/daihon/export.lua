-- 書き出し用の HTML・Markdown を作る。ファイルや画面には触らない（塊の中身は get_part で受け取る）
local parse = require("daihon.parse")
local count = require("daihon.count")

local M = {}

local MAX_DEPTH = 10

-- 組み込みの塊（parts/ ではなく、書き出すときに作る）
M.BUILTINS = { ["@文字数一覧"] = true }

--- 見出しの文字（count の見出しは show の形で文字数を付ける）
local function heading_text(r, n)
  if n and r.heading.show then
    return r.heading.show:format(r.title, count.format(n))
  end
  return r.title
end

--- 書き出す中身を、形式によらない並びにする（PDF・Markdown・Word で同じ決まりにするため）
--- opts = { togaki = true（ト書きも出す）, get_part = fn, summary = count.summary の結果, vertical = 縦書きか }
--- 返す値：items, 未登録の塊の名前のリスト。items の1つは次のどれか
---   { kind = "heading", level, text, new_page }
---   { kind = "line", class, text, speaker, togaki }
---   { kind = "gap" }（空行の空き）
---   { kind = "count_list", rows = { 文字, ... }, total = 文字 }（{@文字数一覧}）
function M.items(records, cfg, opts)
  local pdf = cfg.export.pdf
  local items, missing = {}, {}
  -- 空行の空きは、次に本文が来たときだけ入れる（続けても1つ、見出しの前と最後には入れない）
  local started, pending_gap = false, false

  local function push(item)
    if pending_gap then
      items[#items + 1] = { kind = "gap" }
    end
    items[#items + 1] = item
    started, pending_gap = true, false
  end

  local function line(r, text)
    push({ kind = "line", class = M.class_of(r), text = text, speaker = r.speaker, togaki = r.kind ~= "セリフ" })
  end

  local function part_inline(name)
    local lines = opts.get_part and opts.get_part(name)
    if not lines then
      missing[#missing + 1] = name
      return "{" .. name .. "}"
    end
    return table.concat(lines, " ")
  end

  local function count_list()
    local rows = {}
    for _, r in ipairs(records) do
      local n = opts.summary.headings[r.lnum]
      if n then
        rows[#rows + 1] = heading_text(r, n)
      end
    end
    return { kind = "count_list", rows = rows, total = "合計 : " .. count.format(opts.summary.total) .. "文字" }
  end

  local emit
  emit = function(recs, depth)
    for _, r in ipairs(recs) do
      local refs = r.refs or {}
      local alone = #refs == 1 and parse.trim(r.text) == r.text:sub(refs[1].s, refs[1].e)

      if r.kind == "空行" then
        pending_gap = started
      elseif r.kind == "塊開始" or r.kind == "塊終了" or not (r.kind == "見出し" or r.output) then
        -- 目印とメモは出さない
      elseif r.kind == "見出し" then
        local n = depth == 0 and opts.summary and opts.summary.headings[r.lnum] or nil
        items[#items + 1] = {
          kind = "heading",
          level = math.min(r.level, 6),
          text = heading_text(r, n),
          new_page = pdf.new_page and r.level <= pdf.new_page or false,
        }
        started, pending_gap = false, false
      elseif r.kind ~= "セリフ" and not opts.togaki then
        -- ト書きなし
      elseif alone and refs[1].name == "@文字数一覧" then
        push(count_list())
      elseif alone and depth < MAX_DEPTH then
        local lines = opts.get_part and opts.get_part(refs[1].name)
        if lines then
          emit(parse.parse(lines, cfg), depth + 1)
        else
          missing[#missing + 1] = refs[1].name
          line(r, r.text)
        end
      else
        local text = parse.trim(r.text):gsub("{([^{}]+)}", function(name)
          return part_inline(parse.trim(name))
        end)
        local marks = opts.vertical and pdf.vertical_marks
        if r.range and marks and marks[r.range.op] then
          -- 縦書きでは ▼▲ を読む向きに合う記号にする
          local i = text:find(r.range.mark, 1, true)
          if i then
            text = text:sub(1, i - 1) .. marks[r.range.op] .. text:sub(i + #r.range.mark)
          end
        end
        line(r, text)
      end
    end
  end

  emit(records, 0)
  return items, missing
end

--- 書き出す行のクラス名（CSS で見た目を変えるときに使う）
function M.class_of(r)
  if r.kind == "セリフ" then
    return "serifu"
  end
  return r.type and r.type.class or ("t-" .. r.kind)
end

-- HTML（PDF のもと） --------------------------------------------------

local function esc(s)
  return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end

--- 縦書きで1〜2桁の数字を縦中横にする
local function tcy(s)
  return (s:gsub("%f[%d](%d%d?)%f[%D]", '<span class="tcy">%1</span>'))
end

--- 台本を HTML にする
--- opts = { togaki = true（ト書きも出す）, get_part = fn, title = 題, css = 文字列, summary = count.summary の結果 }
--- 返す値：html, 未登録の塊の名前のリスト
function M.build(records, cfg, opts)
  local pdf = cfg.export.pdf
  local vertical = pdf.vertical ~= false
  local items, missing = M.items(records, cfg, vim.tbl_extend("force", opts, { vertical = vertical }))

  local function text_html(s)
    s = esc(s)
    return vertical and tcy(s) or s
  end

  local body = {}
  for _, it in ipairs(items) do
    if it.kind == "gap" then
      body[#body + 1] = '<p class="gap"></p>'
    elseif it.kind == "heading" then
      local cls = it.new_page and ' class="new-page"' or ""
      body[#body + 1] = ("<h%d%s>%s</h%d>"):format(it.level, cls, text_html(it.text), it.level)
    elseif it.kind == "count_list" then
      body[#body + 1] = '<div class="count-list">'
      for _, row in ipairs(it.rows) do
        body[#body + 1] = ('<p class="count-row">%s</p>'):format(text_html(row))
      end
      body[#body + 1] = ('<p class="count-total">%s</p>'):format(text_html(it.total))
      body[#body + 1] = "</div>"
    else
      local html = text_html(it.text)
      if it.speaker then
        local name = text_html(it.speaker)
        html = html:gsub("^" .. vim.pesc(name), '<span class="speaker">' .. name .. "</span>", 1)
      end
      body[#body + 1] = ('<p class="%s">%s</p>'):format(it.class, html)
    end
  end

  local html = table.concat({
    "<!doctype html>",
    '<html lang="ja">',
    "<head>",
    '<meta charset="utf-8">',
    "<title>" .. esc(opts.title or "台本") .. "</title>",
    "<style>",
    M.css(pdf),
    opts.css or "",
    "</style>",
    "</head>",
    "<body>",
    table.concat(body, "\n"),
    "</body>",
    "</html>",
    "",
  }, "\n")
  return html, missing
end

--- 既定の見た目。export.pdf の値から作る。細かい所は export.pdf.css の自分の CSS で上書きする
function M.css(pdf)
  local vertical = pdf.vertical ~= false
  local page_number = pdf.page_number ~= false
      and "@bottom-center { content: counter(page); font-size: 9pt; writing-mode: horizontal-tb; }"
    or ""
  return table.concat({
    ("@page { size: %s; margin: %s; %s }"):format(pdf.size or "A4 landscape", pdf.margin or "20mm", page_number),
    "html {",
    vertical and "  writing-mode: vertical-rl;" or "",
    ("  font-family: %s;"):format(pdf.font or "serif"),
    ("  font-size: %s;"):format(pdf.font_size or "11pt"),
    ("  line-height: %s;"):format(pdf.line_height or 1.8),
    "}",
    "body { margin: 0; }",
    "p { margin: 0; }",
    "h1 { font-size: 1.6em; margin-block: 0 1em; }",
    "h2 { font-size: 1.25em; margin-block: 1em; }",
    ".new-page { break-before: page; }",
    -- 見出しが続く所と、最初の見出しでは改ページしない
    ".new-page + .new-page, body > .new-page:first-child { break-before: auto; }",
    ".gap { block-size: 0; margin-block-end: 1em; }",
    -- ト書きは行の頭、セリフは1段下げる
    (".serifu { padding-inline-start: %s; }"):format(pdf.serifu_indent or "3em"),
    ".t-指示 { font-size: 0.9em; color: #555; }",
    ".speaker { font-weight: bold; }",
    ".tcy { text-combine-upright: all; }",
    ".count-list { margin-block: 1em; }",
    ".count-total { font-weight: bold; }",
  }, "\n")
end

-- Markdown（Google ドキュメントで開く用） -----------------------------

--- Markdown の記号として読まれないように逃がす
local function md_esc(s)
  s = s:gsub("[\\`*_%[%]<>|~&]", "\\%0")
  -- 行の頭で、見出し・引用・箇条書き・区切り線にならないように
  return (s:gsub("^([#>+%-=])", "\\%1"):gsub("^(%d+)([.)])", "%1\\%2"))
end

--- 台本を Markdown にする（横書き）。opts は build と同じ（title・css は使わない）
--- 空行で区切ったまとまりを1段落にし、中の行は改行（行末の \）でつなぐ。ト書きは斜体
--- 返す値：markdown, 未登録の塊の名前のリスト
function M.markdown(records, cfg, opts)
  local items, missing = M.items(records, cfg, vim.tbl_extend("force", opts, { vertical = false }))
  local blocks, cur = {}, {}

  local function flush()
    if #cur > 0 then
      blocks[#blocks + 1] = table.concat(cur, "\\\n")
      cur = {}
    end
  end

  for _, it in ipairs(items) do
    if it.kind == "gap" then
      flush()
    elseif it.kind == "heading" then
      flush()
      blocks[#blocks + 1] = ("#"):rep(it.level) .. " " .. md_esc(it.text)
    elseif it.kind == "count_list" then
      for _, row in ipairs(it.rows) do
        cur[#cur + 1] = md_esc(row)
      end
      cur[#cur + 1] = "**" .. md_esc(it.total) .. "**"
    elseif it.togaki then
      cur[#cur + 1] = "*" .. md_esc(it.text) .. "*"
    elseif it.speaker and it.text:sub(1, #it.speaker) == it.speaker then
      cur[#cur + 1] = "**" .. md_esc(it.speaker) .. "**" .. md_esc(it.text:sub(#it.speaker + 1))
    else
      cur[#cur + 1] = md_esc(it.text)
    end
  end
  flush()

  return #blocks > 0 and table.concat(blocks, "\n\n") .. "\n" or "", missing
end

return M
