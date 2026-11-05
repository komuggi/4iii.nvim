-- Word（.docx）に書き出す。外の道具は使わず、XML を zip（無圧縮）にまとめて作る
-- ファイルや画面には触らない（できたバイト列を返すだけ）
local export = require("4iii.export")
local bit = require("bit")

local M = {}

-- 長さ・大きさ ---------------------------------------------------------

-- 1 単位あたりの twip（1pt = 20 twip）
local TWIPS = { pt = 20, mm = 1440 / 25.4, cm = 14400 / 25.4, ["in"] = 1440, px = 15 }

--- "20mm" "12pt" などを twip にする。em は文字の大きさ（twip）を掛ける
local function twips(s, em)
  local n, unit = tostring(s or ""):match("^%s*([%d.]+)%s*(%a*)%s*$")
  n = tonumber(n)
  if not n then
    return nil
  end
  if unit == "em" then
    return math.floor(n * em + 0.5)
  end
  return TWIPS[unit] and math.floor(n * TWIPS[unit] + 0.5) or nil
end

-- 紙の大きさ（mm、縦置き）
local PAPER = {
  a3 = { 297, 420 },
  a4 = { 210, 297 },
  a5 = { 148, 210 },
  b4 = { 257, 364 },
  b5 = { 182, 257 },
  letter = { 215.9, 279.4 },
}

--- CSS の @page size（"A4 landscape" "210mm 297mm" など）を幅・高さ（twip）にする
function M.page_size(size)
  local words = vim.split(vim.trim(size or ""), "%s+")
  local landscape = vim.tbl_contains(words, "landscape")
  local w, h = twips(words[1]), twips(words[2])
  if not (w and h) then
    local mm = PAPER[(words[1] or ""):lower()] or PAPER.a4
    w, h = twips(mm[1] .. "mm"), twips(mm[2] .. "mm")
  end
  if landscape and w < h then
    w, h = h, w
  end
  return w, h
end

--- CSS の margin（1〜4つの値）を 上・右・下・左（twip）にする
function M.margins(margin)
  local v = {}
  for word in tostring(margin or ""):gmatch("%S+") do
    v[#v + 1] = twips(word) or twips("20mm")
  end
  if #v == 0 then
    v = { twips("20mm") }
  end
  local t = v[1]
  local r = v[2] or t
  local b = v[3] or t
  return t, r, b, v[4] or r
end

-- XML ----------------------------------------------------------------

local function esc(s)
  s = s:gsub("[%z\1-\8\11\12\14-\31]", "") -- XML に入れられない制御文字
  return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end

local W = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
local R = 'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"'
local HEAD = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'

--- 文字の並び（run）。縦書きでは1〜2桁の数字を縦中横にする
local function runs(text, rpr, vertical)
  rpr = rpr or ""
  local function run(s, extra)
    local props = rpr .. (extra or "")
    props = props ~= "" and ("<w:rPr>" .. props .. "</w:rPr>") or ""
    return ('<w:r>%s<w:t xml:space="preserve">%s</w:t></w:r>'):format(props, esc(s))
  end
  if not vertical then
    return run(text)
  end
  local out, pos = {}, 1
  for s, num, e in text:gmatch("()%f[%d](%d%d?)%f[%D]()") do
    if s > pos then
      out[#out + 1] = run(text:sub(pos, s - 1))
    end
    out[#out + 1] = run(num, ('<w:eastAsianLayout w:id="%d" w:vert="1"/>'):format(#out + 1))
    pos = e
  end
  if pos <= #text then
    out[#out + 1] = run(text:sub(pos))
  end
  return table.concat(out)
end

local function para(style, body, extra)
  local ppr = style and ('<w:pStyle w:val="%s"/>'):format(style) or ""
  ppr = ppr .. (extra or "")
  return ("<w:p>%s%s</w:p>"):format(ppr ~= "" and ("<w:pPr>" .. ppr .. "</w:pPr>") or "", body or "")
end

--- 本文（word/document.xml）
local function document(items, pdf, vertical)
  local body = {}
  local prev_break = true -- 最初の見出しと、見出しが続く所では改ページしない（PDF と同じ）
  for _, it in ipairs(items) do
    local is_break = false
    if it.kind == "gap" then
      body[#body + 1] = para(nil, "")
    elseif it.kind == "heading" then
      is_break = it.new_page
      local extra = (it.new_page and not prev_break) and "<w:pageBreakBefore/>" or nil
      body[#body + 1] = para("Heading" .. it.level, runs(it.text, nil, vertical), extra)
    elseif it.kind == "count_list" then
      for _, row in ipairs(it.rows) do
        body[#body + 1] = para(nil, runs(row, nil, vertical))
      end
      body[#body + 1] = para(nil, runs(it.total, "<w:b/>", vertical))
    else
      local style = it.class == "serifu" and "Serifu" or it.class == "t-指示" and "Shiji" or "Togaki"
      local text, r = it.text, ""
      if it.speaker and text:sub(1, #it.speaker) == it.speaker then
        r = runs(it.speaker, "<w:b/>", vertical)
        text = text:sub(#it.speaker + 1)
      end
      body[#body + 1] = para(style, r .. runs(text, nil, vertical))
    end
    prev_break = is_break
  end

  local w, h = M.page_size(pdf.size)
  local t, r, b, l = M.margins(pdf.margin)
  local foot = pdf.page_number ~= false and '<w:footerReference w:type="default" r:id="rFooter"/>' or ""
  local sect = table.concat({
    "<w:sectPr>",
    foot,
    ('<w:pgSz w:w="%d" w:h="%d"%s/>'):format(w, h, w > h and ' w:orient="landscape"' or ""),
    ('<w:pgMar w:top="%d" w:right="%d" w:bottom="%d" w:left="%d" w:header="567" w:footer="567" w:gutter="0"/>'):format(
      t,
      r,
      b,
      l
    ),
    vertical and '<w:textDirection w:val="tbRl"/>' or "",
    "</w:sectPr>",
  })
  return HEAD .. ("<w:document %s %s><w:body>"):format(W, R) .. table.concat(body) .. sect .. "</w:body></w:document>"
end

--- 見た目（word/styles.xml）。Word の「スタイル」なので、受け取った人が Word で変えられる
local function styles(pdf)
  local pt = tonumber(tostring(pdf.font_size or ""):match("^%s*([%d.]+)%s*pt")) or 12
  local half = function(scale) -- Word の文字の大きさは半ポイント
    return math.floor(pt * 2 * scale + 0.5)
  end
  local font = esc(vim.trim((tostring(pdf.font or ""):match("^([^,]+)") or ""):gsub("[\"']", "")))
  local line = math.floor(240 * (tonumber(pdf.line_height) or 1.8) + 0.5)
  local indent = twips(pdf.serifu_indent or "3em", pt * 20) or 0

  local function style(id, name, ppr, rpr, based)
    return table.concat({
      ('<w:style w:type="paragraph" w:styleId="%s"><w:name w:val="%s"/>'):format(id, name),
      ('<w:basedOn w:val="%s"/>'):format(based or "Normal"),
      "<w:qFormat/>",
      ppr and ("<w:pPr>" .. ppr .. "</w:pPr>") or "",
      rpr and ("<w:rPr>" .. rpr .. "</w:rPr>") or "",
      "</w:style>",
    })
  end

  local out = {
    HEAD,
    ("<w:styles %s>"):format(W),
    "<w:docDefaults><w:rPrDefault><w:rPr>",
    font ~= "" and ('<w:rFonts w:ascii="%s" w:hAnsi="%s" w:eastAsia="%s" w:cs="%s"/>'):format(font, font, font, font)
      or "",
    ('<w:sz w:val="%d"/><w:szCs w:val="%d"/>'):format(half(1), half(1)),
    '<w:lang w:val="ja-JP" w:eastAsia="ja-JP"/>',
    "</w:rPr></w:rPrDefault><w:pPrDefault><w:pPr>",
    ('<w:spacing w:before="0" w:after="0" w:line="%d" w:lineRule="auto"/>'):format(line),
    "</w:pPr></w:pPrDefault></w:docDefaults>",
    '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style>',
    -- ト書きは行の頭、セリフは字下げ（PDF と同じ）
    style("Serifu", "セリフ", ('<w:ind w:left="%d"/>'):format(indent)),
    style("Togaki", "ト書き"),
    style("Shiji", "指示", nil, ('<w:color w:val="555555"/><w:sz w:val="%d"/>'):format(half(0.9)), "Togaki"),
  }
  local sizes = { 1.6, 1.25 }
  for level = 1, 6 do
    local before = level == 1 and 0 or pt * 20
    out[#out + 1] = style(
      "Heading" .. level,
      "heading " .. level,
      ('<w:keepNext/><w:spacing w:before="%d" w:after="%d"/><w:outlineLvl w:val="%d"/>'):format(
        before,
        pt * 20,
        level - 1
      ),
      ('<w:b/><w:sz w:val="%d"/>'):format(half(sizes[level] or 1))
    )
  end
  out[#out + 1] = "</w:styles>"
  return table.concat(out)
end

--- ページ番号（word/footer1.xml）。縦書きでも番号は横書きで下の真ん中に
local function footer()
  local sz = '<w:rPr><w:sz w:val="18"/></w:rPr>'
  return HEAD
    .. ("<w:ftr %s>"):format(W)
    .. '<w:p><w:pPr><w:spacing w:line="240" w:lineRule="auto"/><w:jc w:val="center"/></w:pPr>'
    .. ('<w:r>%s<w:fldChar w:fldCharType="begin"/></w:r>'):format(sz)
    .. ('<w:r>%s<w:instrText xml:space="preserve"> PAGE </w:instrText></w:r>'):format(sz)
    .. ('<w:r>%s<w:fldChar w:fldCharType="separate"/></w:r>'):format(sz)
    .. ("<w:r>%s<w:t>1</w:t></w:r>"):format(sz)
    .. ('<w:r>%s<w:fldChar w:fldCharType="end"/></w:r>'):format(sz)
    .. "</w:p></w:ftr>"
end

local CONTENT_TYPES = HEAD
  .. '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
  .. '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
  .. '<Default Extension="xml" ContentType="application/xml"/>'
  .. '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
  .. '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
  .. '<Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>'
  .. "</Types>"

local ROOT_RELS = HEAD
  .. '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
  .. '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
  .. "</Relationships>"

local DOC_RELS = HEAD
  .. '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
  .. '<Relationship Id="rStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
  .. '<Relationship Id="rFooter" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="footer1.xml"/>'
  .. "</Relationships>"

-- zip（無圧縮） --------------------------------------------------------

local crc_table
local function crc32(s)
  if not crc_table then
    crc_table = {}
    for i = 0, 255 do
      local c = i
      for _ = 1, 8 do
        c = bit.band(c, 1) ~= 0 and bit.bxor(0xEDB88320, bit.rshift(c, 1)) or bit.rshift(c, 1)
      end
      crc_table[i] = c
    end
  end
  local crc = bit.bnot(0)
  for i = 1, #s do
    crc = bit.bxor(bit.rshift(crc, 8), crc_table[bit.band(bit.bxor(crc, s:byte(i)), 0xFF)])
  end
  return bit.bnot(crc)
end

local function u16(n)
  return string.char(bit.band(n, 0xFF), bit.band(bit.rshift(n, 8), 0xFF))
end

local function u32(n)
  return u16(bit.band(n, 0xFFFF)) .. u16(bit.rshift(n, 16))
end

--- ファイルの並び { { name, data }, ... } を zip のバイト列にする。日付は 1980-01-01 で固定
function M.zip(files)
  local out, central, offset = {}, {}, 0
  local DATE = u16(0) .. u16(33) -- 時刻 0:00・日付 1980-01-01
  for _, f in ipairs(files) do
    local name, data = f[1], f[2]
    local crc = crc32(data)
    local common = u16(20) .. u16(0) .. u16(0) .. DATE .. u32(crc) .. u32(#data) .. u32(#data) .. u16(#name) .. u16(0)
    local header = u32(0x04034b50) .. common .. name
    out[#out + 1] = header .. data
    central[#central + 1] = u32(0x02014b50)
      .. u16(20)
      .. common
      .. u16(0)
      .. u16(0)
      .. u16(0)
      .. u32(0)
      .. u32(offset)
      .. name
    offset = offset + #header + #data
  end
  local cd = table.concat(central)
  local eocd = u32(0x06054b50) .. u16(0) .. u16(0) .. u16(#files) .. u16(#files) .. u32(#cd) .. u32(offset) .. u16(0)
  return table.concat(out) .. cd .. eocd
end

-- 組み立て ------------------------------------------------------------

--- 台本を .docx のバイト列にする。opts は export.build と同じ（title・css は使わない）
--- 縦書き・紙・余白・字・字下げ・改ページ・ページ番号は export.pdf の設定に合わせる
--- 返す値：バイト列, 未登録の塊の名前のリスト
function M.build(records, cfg, opts)
  local pdf = cfg.export.pdf
  local vertical = pdf.vertical ~= false
  local items, missing = export.items(records, cfg, vim.tbl_extend("force", opts, { vertical = vertical }))
  local files = {
    { "[Content_Types].xml", CONTENT_TYPES },
    { "_rels/.rels", ROOT_RELS },
    { "word/_rels/document.xml.rels", DOC_RELS },
    { "word/document.xml", document(items, pdf, vertical) },
    { "word/styles.xml", styles(pdf) },
    { "word/footer1.xml", footer() },
  }
  return M.zip(files), missing
end

return M
