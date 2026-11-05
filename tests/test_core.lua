local config = require("4iii.config")
local parse = require("4iii.parse")
local count = require("4iii.count")

local function cfg(over)
  return config.merge(config.defaults, over)
end

local function kinds(records)
  local out = {}
  for _, r in ipairs(records) do
    out[#out + 1] = r.kind
  end
  return out
end

local function msgs(issues)
  local out = {}
  for _, i in ipairs(issues) do
    out[#out + 1] = i.lnum .. ":" .. i.msg
  end
  return out
end

-- 設定 ------------------------------------------------------------

test("設定：表は中まで重ね、リストは置き換える", function()
  local c = cfg({ count = { ignore_chars = "…" }, line_types = { { name = "指示", prefix = "//" } } })
  eq({ "セリフ" }, c.count.include)
  eq("…", c.count.ignore_chars)
  eq(1, #c.line_types)
end)

test("設定：まちがいを知らせる", function()
  eq(false, (config.validate(cfg({ mode = "two" }))))
  eq(false, (config.validate(cfg({ line_types = { { name = "セリフ", prefix = "!" } } }))))
  eq(false, (config.validate(cfg({ line_types = { { name = "指示" } } }))))
  eq(true, (config.validate(cfg())))
end)

-- 行の種類 --------------------------------------------------------

test("1人：記号のない行はセリフ", function()
  local r = parse.parse({
    "# 本編",
    "## Track 01",
    "(放課後の教室)",
    "// SE : 足音",
    "",
    "おかえり",
    "¥ ここもう少し甘く",
    "（全角かっこの場面）",
    "￥ 全角の円記号",
    "【正面・近】",
  }, cfg())
  eq(
    { "見出し", "見出し", "場面", "指示", "空行", "セリフ", "メモ", "場面", "メモ", "位置" },
    kinds(r)
  )
  eq("正面・近", r[10].body)
  eq("Track 01", r[2].title)
  eq("放課後の教室", r[3].body)
  eq("SE : 足音", r[4].body)
  eq(false, r[7].output)
end)

test("複数人：名前「セリフ」と 名前：セリフ", function()
  local r = parse.parse({ "妹「おかえり」", "　姉「遅かったね」" }, cfg({ mode = "multi" }))
  eq("妹", r[1].speaker)
  eq("おかえり", r[1].body)
  eq("姉", r[2].speaker)
  eq({ 3, 6 }, r[2].speaker_col)

  r = parse.parse({ "妹：おかえり", "姉:ただいま" }, cfg({ mode = "multi", multi = { style = "colon" } }))
  eq("妹", r[1].speaker)
  eq("おかえり", r[1].body)
  eq("ただいま", r[2].body)
end)

test("塊：{{名前 〜 }} と {名前}", function()
  local r = parse.parse({ "{{あいさつ1", "おかえり", "}}", "そして {あいさつ2} も" }, cfg())
  eq({ "塊開始", "セリフ", "塊終了", "セリフ" }, kinds(r))
  eq("あいさつ1", r[1].block_name)
  eq("あいさつ1", r[2].in_block)
  eq("あいさつ2", r[4].refs[1].name)
  eq(0, #parse.find_refs("{{あいさつ1"))
end)

test("見出しの記号は設定で変えられる", function()
  local r =
    parse.parse({ "Track 01", "本文" }, cfg({ headings = { { level = 2, prefix = "Track ", count = true } } }))
  eq("見出し", r[1].kind)
  eq("01", r[1].title)
end)

-- ▼▲ -------------------------------------------------------------

test("▼▲：入れ子で正しく閉じれば何も出ない", function()
  local r = parse.parse({
    "// ▼前・密",
    "// ▼キスしながら",
    "ちゅっ",
    "// ▲キスしながら",
    "// ▲前・密",
    "(▼呂律が回らない)",
    "(▲呂律が回らない)",
    "//▲無声", -- 記号のあとに空白がなくても読む（対応がないので警告）
  }, cfg())
  eq({ "8:▲無声 に対応する ▼無声 がありません" }, msgs(parse.check_ranges(r, cfg())))
end)

test("▼▲：範囲は重ねてよい（閉じる順番は見ない）", function()
  local r = parse.parse({ "// ▼SE : 水音", "// ▼ささやき", "// ▲SE : 水音", "// ▲ささやき" }, cfg())
  eq({}, msgs(parse.check_ranges(r, cfg())))
end)

test("▼▲：閉じのラベルは頭だけでもよい。同じラベルを優先する", function()
  local r = parse.parse({ "// ▼口内→ごっくん", "// ▼口", "// ▲口", "// ▲口内" }, cfg())
  eq({}, msgs(parse.check_ranges(r, cfg())))
  r = parse.parse({ "// ▼前", "// ▲前・中" }, cfg()) -- 閉じの方が長いのはだめ
  eq(2, #parse.check_ranges(r, cfg()))
  r = parse.parse({ "// ▼前", "// ▲" }, cfg()) -- ラベルなしの ▲ では閉じない
  eq(2, #parse.check_ranges(r, cfg()))
end)

test("▼▲：その行の手前で開いているもの（▲ の候補）", function()
  local r = parse.parse(
    { "## Track 01", "// ▼左", "## Track 02", "// ▼前・中", "// ▼SE : 足音", "// ▲前・中", "" },
    cfg()
  )
  local labels = {}
  for _, o in ipairs(parse.open_ranges_at(r, cfg(), 7)) do
    labels[#labels + 1] = o.label
  end
  eq({ "SE : 足音" }, labels)
  eq(2, #parse.open_ranges_at(r, cfg(), 6))
end)

test("▼▲：見出しやファイルの終わりまでに閉じていない", function()
  local r = parse.parse({ "## Track 01", "// ▼前・中", "## Track 02", "// ▼左前" }, cfg())
  eq({
    "2:▼前・中 が閉じていません（次の見出しまでに ▲前・中 が要ります）",
    "4:▼左前 が閉じていません（ファイルの終わりまでに ▲左前 が要ります）",
  }, msgs(parse.check_ranges(r, cfg())))
end)

test("▼▲：記号は設定で変えられる", function()
  local c = cfg({ ranges = { open = "<<", close = ">>", in_types = { "指示" } } })
  local r = parse.parse({ "// <<前", "// >>前" }, c)
  eq({}, msgs(parse.check_ranges(r, c)))
end)

-- 文字数 ----------------------------------------------------------

test("文字数：空白・全角スペースは数えない。数えない記号を足せる", function()
  eq(4, count.chars("お か　えり"))
  eq(4, count.chars("おかえり…。", count.char_set("…。")))
  eq("3,369", count.format(3369))
  eq("1,234,567", count.format(1234567))
  eq("12", count.format(12))
end)

test("文字数：既定はセリフだけ。ト書きも数えられる", function()
  local c = cfg()
  local lines =
    { "## Track 01", "(教室)", "// SE : 足音", "おかえり", "¥ メモは数えない", "ただいま" }
  local r = parse.parse(lines, c)
  eq(8, count.summary(r, count.context(c)).total)
  eq(15, count.summary(r, count.context(c, nil, { "セリフ", "指示", "場面" })).total)
end)

test("文字数：見出しごと", function()
  local c = cfg()
  local r = parse.parse(
    { "# 本編", "## Track 01", "あいう", "## Track 02", "かき", "# 特典", "## おまけ", "さ" },
    c
  )
  local s = count.summary(r, count.context(c))
  eq(3, s.headings[2])
  eq(2, s.headings[4])
  eq(1, s.headings[7])
  eq(nil, s.headings[1]) -- count = true の見出しだけ
end)

test("文字数：{名前} は中身で数える。未登録は 0、メモの中は数えない", function()
  local c = cfg()
  local parts = {
    ["あいさつ1"] = { "おかえり", "// 指示は数えない" },
    ["入れ子"] = { "{あいさつ1}です" },
    ["自分"] = { "{自分}" },
  }
  local ctx = count.context(c, function(name)
    return parts[name]
  end)
  local r = parse.parse({ "{あいさつ1}", "そして{入れ子}", "{ない}", "¥ {あいさつ1}", "{自分}" }, c)
  local s = count.summary(r, ctx)
  eq({ 4, 3 + 6, 0, 0, 0 }, { s.lines[1], s.lines[2], s.lines[3], s.lines[4], s.lines[5] })
  eq(false, ctx.has_part("ない"))
end)

test("文字数：複数人は名前とかっこを数えない", function()
  local c = cfg({ mode = "multi" })
  local r = parse.parse({ "妹「おかえり」" }, c)
  eq(4, count.summary(r, count.context(c)).total)
end)

test("▼▲：ラベルの空白の違いは無視する", function()
  local r = parse.parse({ "// ▼SE : 水音", "// ▲SE :水音", "// ▼前　中", "// ▲前中" }, cfg())
  eq({}, msgs(parse.check_ranges(r, cfg())))
end)

test("文字数：長いセリフに印。{名前} の字面は数えない。false で付けない", function()
  local c = cfg()
  local lines = { string.rep("あ", 30), string.rep("い", 31) }
  lines[3] = "// " .. string.rep("う", 40)
  lines[4] = "{" .. string.rep("え", 40) .. "}"
  local r = parse.parse(lines, c)
  eq({ { lnum = 2, n = 31 } }, count.long_lines(r, count.context(c), 30))
  eq({}, count.long_lines(r, count.context(c), false))
end)

-- 作品ごとの設定を安全に読む ------------------------------------------

test("安全：4iii.lua は表を返すだけ。nvim・ファイルには触れない", function()
  eq({ mode = "multi" }, config.run_sandboxed('return { mode = "multi" }', "t"))
  eq({ n = 3 }, config.run_sandboxed('local s = ("abc"):upper() return { n = #s }', "t"))
  for _, src in ipairs({
    "return vim.fn.system('ls')",
    "return io.open('/etc/hosts')",
    "return os.execute('ls')",
    "return require('x')",
  }) do
    eq(nil, (config.run_sandboxed(src, "t")), src)
  end
end)

test("安全：止まらない・大きすぎる 4iii.lua は止める", function()
  local res, err = config.run_sandboxed("while true do end", "t")
  eq(nil, res)
  eq(true, err:find("長すぎる") ~= nil)
  res, err = config.run_sandboxed('local s = "x" for i = 1, 40 do s = s .. s end return {}', "t")
  eq(nil, res)
  eq(true, err:find("大きすぎる") ~= nil)
  eq(nil, (config.run_sandboxed('return { s = ("x"):rep(1e10) }', "t")))
  eq("XYZ", ("xyz"):upper()) -- 終わったら文字列の操作は元に戻る
  eq("aa", ("a"):rep(2))
end)

test("安全：PDF のコマンドは作品ごとの設定では変えられない", function()
  local p = { export = { pdf = { command = { "rm", "-rf", "/" }, size = "A5" } } }
  eq({ "export.pdf.command" }, config.strip_global_only(p))
  eq({ export = { pdf = { size = "A5" } } }, p)
end)

test("安全：parts と out は作品フォルダの中だけ", function()
  eq(true, config.inside("parts"))
  eq(true, config.inside("out/pdf"))
  for _, bad in ipairs({ "../x", "/tmp", "~/x", "a/../../b", "C:/x", "" }) do
    eq(false, config.inside(bad), bad)
  end
  eq(false, (config.validate(cfg({ parts_dir = "../../.ssh" }))))
  eq(false, (config.validate(cfg({ export = { dir = "/tmp" } }))))
end)

test("文字数の表示：カーソルのあるトラックと全体", function()
  local c = cfg()
  local r = parse.parse({ "# 本編", "## Track 01", "あいう", "## Track 02", "かき", "# 特典", "さ" }, c)
  local s = count.summary(r, count.context(c))
  eq("Track 01 3文字 ／ 全体 6文字", count.bar_text(r, s, 3))
  eq("Track 02 2文字 ／ 全体 6文字", count.bar_text(r, s, 5))
  eq("全体 6文字", count.bar_text(r, s, 1))
  eq("全体 6文字", count.bar_text(r, s, 7)) -- 数えない見出しの下
end)
