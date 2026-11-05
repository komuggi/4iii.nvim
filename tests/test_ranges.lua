local config = require("4iii.config")
local parse = require("4iii.parse")
local count = require("4iii.count")

local cfg = config.merge(config.defaults, {})

test("範囲：行の頭の ▼▲ は範囲の行。文字数に入れない", function()
  local r = parse.parse({ "▼前・中", "おかえり", "▲前・中", "  ▼右" }, cfg)
  eq({ "範囲", "セリフ", "範囲", "範囲" }, { r[1].kind, r[2].kind, r[3].kind, r[4].kind })
  eq("前・中", r[1].range.label)
  eq(2, r[4].range.col)
  eq(4, count.summary(r, count.context(cfg)).total)
  eq(
    { "4:▼右 が閉じていません（ファイルの終わりまでに ▲右 が要ります）" },
    vim.tbl_map(function(i)
      return i.lnum .. ":" .. i.msg
    end, parse.check_ranges(r, cfg))
  )
end)

test("範囲：縦の線のための、行ごとの囲み", function()
  local r =
    parse.parse({ "▼前", "あ", "// ▼ささやき", "い", "▲ささやき", "う", "▲前", "え" }, cfg)
  local d = parse.range_depths(r, cfg)
  local labels = function(n)
    return vim.tbl_map(function(o)
      return o.label
    end, d[n] or {})
  end
  eq({}, labels(1))
  eq({ "前" }, labels(2))
  eq({ "前" }, labels(3))
  eq({ "前", "ささやき" }, labels(4))
  eq({ "前" }, labels(5))
  eq({ "前" }, labels(6))
  eq({}, labels(7))
  eq({}, labels(8))
end)

test("範囲：重ねた範囲も、閉じた所から線が減る", function()
  local r = parse.parse({ "▼SE", "▼声", "あ", "▲SE", "い", "▲声" }, cfg)
  local d = parse.range_depths(r, cfg)
  eq(2, #d[3])
  eq({ "声" }, { d[5][1].label })
end)

test("範囲：▼ の行から ▲ の行を作る。下に閉じがあるか", function()
  local r = parse.parse({ "▼前・中", "// ▼ささやき", "(▼呂律)" }, cfg)
  eq("▲前・中", parse.close_text(r[1], cfg))
  eq("// ▲ささやき", parse.close_text(r[2], cfg))
  eq("(▲呂律)", parse.close_text(r[3], cfg))
  local below = parse.parse({ "あ", "▲前" }, cfg)
  eq(true, parse.has_close_below(below, "前・中"))
  eq(false, parse.has_close_below(parse.parse({ "あ", "## Track 02", "▲前・中" }, cfg), "前・中"))
  eq(false, parse.has_close_below(parse.parse({ "▼前・中", "▲前・中" }, cfg), "前・中"))
end)
