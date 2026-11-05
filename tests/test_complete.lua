local config = require("4iii.config")
local parse = require("4iii.parse")
local complete = require("4iii.complete")

local cfg = config.merge(config.defaults, {})

local function words(items)
  return vim.tbl_map(function(it)
    return it.word
  end, items)
end

test("候補：▼ のあとは、使ったラベル（多い順）→ 位置×距離", function()
  local above = parse.parse({ "// ▼右・近", "// ▲右・近", "// ▼ささやき", "// ▼右・近" }, cfg)
  local c = complete.at("// ▼", above, cfg)
  eq(true, c.auto)
  eq(#"// ▼", c.col)
  eq({ "右・近", "ささやき", "前・遠", "前・中" }, vim.list_slice(words(c.items), 1, 4))
  eq(2 + 5 * 4 - 1, #c.items) -- 右・近 は位置×距離にもあるので1つにまとまる
end)

test("候補：▼ のあと打った分で絞る。打ちかけなら自動では出さない", function()
  local c = complete.at("// ▼右", {}, cfg)
  eq(false, c.auto)
  eq(#"// ▼", c.col)
  local want = { "右前・遠", "右前・中", "右前・近", "右前・密" }
  vim.list_extend(want, { "右・遠", "右・中", "右・近", "右・密" })
  eq(want, words(complete.filter(c.items, "右")))
end)

test("候補：▲ のあとは、まだ閉じていない ▼（新しい順）", function()
  local above = parse.parse({ "## Track 01", "// ▼前・中", "// ▼ささやき", "// ▲前・中" }, cfg)
  local c = complete.at("(▲", above, cfg)
  eq({ "ささやき" }, words(c.items))
  eq("3行目", c.items[1].menu)
end)

test("候補：位置と距離は設定で変えられる。▼▲ の行でなければ出さない", function()
  local c2 =
    config.merge(cfg, { ranges = { position = { "正面" }, distance = { "密着" }, words = { "無声音" } } })
  eq({ "正面・密着", "無声音" }, words(complete.at("// ▼", {}, c2).items))
  eq(nil, complete.at("おかえり", {}, cfg))
  eq(false, complete.at("// SE", {}, cfg).auto) -- 指示の行は <C-x><C-o> のときだけ
end)

test("候補：SE : のあとは、登録した言葉 → 使った SE（多い順）", function()
  local c2 = config.merge(cfg, { words = { se = { "衣擦れ", "足音" } } })
  local above = parse.parse(
    { "// SE : ドアが開く・足音", "// SE：ドアが開く", "// ▼前・中", "// 耳元で" },
    c2
  )
  local c = complete.at("// SE : ", above, c2)
  eq(true, c.auto)
  eq(#"// SE : ", c.col)
  eq({ "衣擦れ", "足音", "ドアが開く" }, words(c.items))
  eq(
    { "登録", "登録", "使った" },
    vim.tbl_map(function(it)
      return it.menu
    end, c.items)
  )
end)

test("候補：SE の「・」のあとも出す。打ちかけなら自動では出さない", function()
  local c = complete.at("// SE : ドアが開く・", {}, cfg)
  eq(true, c.auto)
  eq(#"// SE : ドアが開く・", c.col)
  c = complete.at("// SE : ドア", {}, cfg)
  eq(false, c.auto)
  eq(#"// SE : ", c.col)
end)

test("候補：ほかの指示は <C-x><C-o> のときだけ。登録 → 使った指示", function()
  local c2 = config.merge(cfg, { words = { shiji = { "吐息まじりに" } } })
  local above = parse.parse({ "// 耳元で", "// SE : 足音", "// ▼前", "// 耳元で", "// 笑いながら" }, c2)
  local c = complete.at("// ", above, c2)
  eq(false, c.auto)
  eq({ "吐息まじりに", "耳元で", "笑いながら" }, words(c.items))
end)

test("候補：言葉は台本全体から、▲ は上の行から", function()
  local all = parse.parse({ "// ▼前", "// SE : 足音", "", "// SE : 衣擦れ", "// ▼右" }, cfg)
  local above = vim.list_slice(all, 1, 2)
  eq({ "足音", "衣擦れ" }, words(complete.at("// SE : ", above, cfg, all).items))
  eq({ "前" }, words(complete.at("// ▲", above, cfg, all).items))
end)
