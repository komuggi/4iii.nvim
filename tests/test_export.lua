local config = require("4iii.config")
local parse = require("4iii.parse")
local count = require("4iii.count")
local export = require("4iii.export")

local function build(lines, togaki, over)
  local cfg = config.merge(config.defaults, over)
  local parts = { ["あいさつ"] = { "// ▼右・近", "おかえり" }, ["短い"] = { "またね" } }
  local get = function(n)
    return parts[n]
  end
  local records = parse.parse(lines, cfg)
  local summary = count.summary(records, count.context(cfg, get))
  return export.build(records, cfg, { togaki = togaki, get_part = get, summary = summary, title = "t" })
end

local function has(html, s)
  if not html:find(s, 1, true) then
    error("ない: " .. s, 2)
  end
end

local function hasnt(html, s)
  if html:find(s, 1, true) then
    error("あってはいけない: " .. s, 2)
  end
end

test("書き出し：ト書きあり／なし。メモと塊の目印は出さない", function()
  local lines =
    { "## Track 01", "(玄関)", "// SE : 足音", "ただいま", "¥ メモ", "{{短い", "またね", "}}" }
  local a = build(lines, true)
  has(a, '<p class="t-場面">(玄関)</p>')
  has(a, '<p class="t-指示">// SE : 足音</p>')
  has(a, '<p class="serifu">ただいま</p>')
  hasnt(a, "メモ")
  hasnt(a, "{{")
  local b = build(lines, false)
  hasnt(b, "玄関")
  hasnt(b, "足音")
  has(b, '<p class="serifu">ただいま</p>')
end)

test("書き出し：見出しに文字数。{@文字数一覧}", function()
  local html =
    build({ "{@文字数一覧}", "# 本編", "## Track 01", "ただいま", "## Track 02", "{短い}" }, true)
  has(html, 'Track <span class="tcy">01</span> : <span class="tcy">4</span>文字')
  has(html, '<p class="count-total">合計 : <span class="tcy">7</span>文字</p>')
  has(html, '<h2 class="new-page">')
end)

test("書き出し：塊は中身に置き換える。1行なら行ごと、途中なら文の中に", function()
  local a = build({ "{あいさつ}", "また{短い}" }, true)
  has(a, '<p class="t-指示">// ◀右・近</p>')
  has(a, '<p class="serifu">おかえり</p>')
  has(a, '<p class="serifu">またまたね</p>')
  local b = build({ "{あいさつ}" }, false)
  hasnt(b, "右・近")
  local _, missing = build({ "{ない}" }, true)
  eq({ "ない" }, missing)
end)

test("書き出し：HTML の記号は逃がす。横書きにもできる", function()
  local html = build({ "<b>&" }, true, { export = { pdf = { vertical = false } } })
  has(html, "&lt;b&gt;&amp;")
  hasnt(html, "vertical-rl")
  has(build({ "あ" }, true), "writing-mode: vertical-rl")
end)

test("書き出し：空行は続けても1つ", function()
  local html = build({ "あ", "", "", "// 指示", "", "い" }, false)
  local _, n = html:gsub('class="gap"', "")
  eq(1, n)
end)

test("書き出し：見出しの前と最後には空きを入れない", function()
  local html = build({ "あ", "", "## Track 01", "", "い", "" }, true)
  local _, n = html:gsub('class="gap"', "")
  eq(0, n)
end)

test(
  "書き出し：縦書きでは ▼▲ を ◀▶ にする（始まり ◀・終わり ▶）。横書きと設定で外したときはそのまま",
  function()
    local lines = { "// ▼前・中", "おかえり", "// ▲前・中", "// ▼と書いた文の中の▼" }
    local v = build(lines, true)
    has(v, "// ◀前・中")
    has(v, "// ▶前・中")
    has(v, "// ◀と書いた文の中の▼")
    local h = build(lines, true, { export = { pdf = { vertical = false } } })
    has(h, "// ▼前・中")
    local off = build(lines, true, { export = { pdf = { vertical_marks = false } } })
    has(off, "// ▼前・中")
  end
)

test("書き出し：セリフは字下げ、ト書きは行の頭", function()
  local html = build({ "あ" }, true)
  has(html, ".serifu { padding-inline-start: 3em; }")
  hasnt(html, ".t-指示 { padding-inline-start")
end)

local function md(lines, togaki)
  local cfg = config.merge(config.defaults, {})
  local parts = { ["あいさつ"] = { "// ▼右・近", "おかえり" } }
  local get = function(n)
    return parts[n]
  end
  local records = parse.parse(lines, cfg)
  local summary = count.summary(records, count.context(cfg, get))
  return export.markdown(records, cfg, { togaki = togaki, get_part = get, summary = summary })
end

test(
  "Markdown：見出しに文字数。ト書きは斜体。空行で段落を分け、中は改行でつなぐ",
  function()
    local lines = { "## Track 01", "(玄関)", "ただいま", "おかえり", "", "¥ メモ", "またね" }
    eq("## Track 01 : 11文字\n\n*(玄関)*\\\nただいま\\\nおかえり\n\nまたね\n", (md(lines, true)))
    eq("## Track 01 : 11文字\n\nただいま\\\nおかえり\n\nまたね\n", (md(lines, false)))
  end
)

test("Markdown：塊は中身に。▼▲ はそのまま。{@文字数一覧}", function()
  local out = md({ "{@文字数一覧}", "## Track 01", "{あいさつ}" }, true)
  has(out, "Track 01 : 4文字\\\n**合計 : 4文字**")
  has(out, "*// ▼右・近*\\\nおかえり")
  local _, missing = md({ "{ない}" }, true)
  eq({ "ない" }, missing)
end)

test("Markdown：記号は逃がす。話す人の名前は太字", function()
  eq("a\\*b\\_c\\[d\\]\n", (md({ "a*b_c[d]" }, true)))
  eq("\\- 番\n", (md({ "- 番" }, true)))
  eq("1\\. 番\n", (md({ "1. 番" }, true)))
  local cfg = config.merge(config.defaults, { mode = "multi", characters = { "ミカ" } })
  local records = parse.parse({ "ミカ「ただいま」" }, cfg)
  eq(
    "**ミカ**「ただいま」\n",
    (export.markdown(records, cfg, { togaki = true, summary = count.summary(records, count.context(cfg)) }))
  )
end)

local docx = require("4iii.docx")

--- 無圧縮の zip から、名前でファイルの中身を取り出す（テスト用）
local function unzip(bytes, name)
  local i = bytes:find(name, 1, true)
  local head = bytes:sub(i - 30, i - 1)
  local size = head:byte(19) + head:byte(20) * 256 + head:byte(21) * 65536
  return bytes:sub(i + #name, i + #name + size - 1)
end

local function doc_xml(lines, togaki, over)
  local cfg = config.merge(config.defaults, over)
  local parts = { ["あいさつ"] = { "// ▼右・近", "おかえり" } }
  local get = function(n)
    return parts[n]
  end
  local records = parse.parse(lines, cfg)
  local summary = count.summary(records, count.context(cfg, get))
  local bytes, missing = docx.build(records, cfg, { togaki = togaki, get_part = get, summary = summary })
  return unzip(bytes, "word/document.xml"), missing, bytes
end

test("Word：zip の形（先頭の印・CRC・中のファイル）", function()
  local z = docx.zip({ { "a.txt", "123456789" } })
  eq("PK\3\4", z:sub(1, 4))
  eq("\38\57\244\203", z:sub(15, 18)) -- CRC32("123456789") = CBF43926
  eq("123456789", unzip(z, "a.txt"))
  local _, _, bytes = doc_xml({ "あ" }, true)
  for _, name in ipairs({ "[Content_Types].xml", "_rels/.rels", "word/document.xml", "word/styles.xml" }) do
    if not bytes:find(name, 1, true) then
      error("ない: " .. name)
    end
  end
end)

test(
  "Word：ト書きあり／なし。セリフとト書きのスタイル。▼▲ は縦書きで ◀▶",
  function()
    local lines = { "## Track 01", "(玄関)", "ただいま", "¥ メモ", "{あいさつ}" }
    local a, missing = doc_xml(lines, true)
    eq({}, missing)
    has(a, '<w:pStyle w:val="Togaki"/>')
    has(a, '<w:pStyle w:val="Serifu"/>')
    has(a, '<w:pStyle w:val="Shiji"/></w:pPr><w:r><w:t xml:space="preserve">// ◀右・近</w:t>')
    has(a, "ただいま")
    hasnt(a, "メモ")
    has(a, '<w:textDirection w:val="tbRl"/>')
    local b = doc_xml(lines, false)
    hasnt(b, "玄関")
    hasnt(b, "右・近")
    has(b, "おかえり")
  end
)

test("Word：見出しに文字数・縦中横・改ページ。横書きにもできる", function()
  local x = doc_xml({ "# 本編", "## Track 01", "あ", "## Track 02", "い" }, true)
  has(x, '<w:pStyle w:val="Heading2"/>')
  has(x, '<w:eastAsianLayout w:id="2" w:vert="1"/></w:rPr><w:t xml:space="preserve">01</w:t>')
  local _, n = x:gsub("<w:pageBreakBefore/>", "")
  eq(1, n) -- 見出しが続く所（本編 → Track 01）では改ページしない
  has(x, 'w:orient="landscape"')
  local h = doc_xml({ "// ▼右", "<&>" }, true, { export = { pdf = { vertical = false, size = "A5" } } })
  hasnt(h, "tbRl")
  hasnt(h, "eastAsianLayout")
  has(h, "// ▼右")
  has(h, "&lt;&amp;&gt;")
  has(h, '<w:pgSz w:w="8391" w:h="11906"/>')
end)
