local config = require("4iii.config")
local parse = require("4iii.parse")
local blocks = require("4iii.blocks")

local cfg = config.merge(config.defaults, {})

test("塊：名前に使えるか", function()
  eq(true, blocks.valid_name("あいさつ1"))
  eq(false, blocks.valid_name("../外"))
  eq(false, blocks.valid_name(".隠し"))
  eq(false, blocks.valid_name(""))
end)

test("塊：中身を読むのは parts/ の中だけ", function()
  local root = vim.fn.tempname()
  vim.fn.mkdir(root .. "/parts", "p")
  vim.fn.writefile({ "あいさつ" }, root .. "/parts/A.txt")
  vim.fn.writefile({ "外の台本" }, root .. "/外.txt")
  local st = { root = root, cfg = cfg }
  eq({ "あいさつ" }, blocks.read_part(st, "A"))
  eq(nil, blocks.read_part(st, "../外")) -- {../外} と書いても parts/ の外は読まない
  eq(nil, blocks.read_part(st, "無い"))
end)

test("塊：その行を囲んでいる {{ }} を探す", function()
  local r = parse.parse({ "前", "{{A", "中", "}}", "後", "{{B", "閉じていない" }, cfg)
  eq(nil, blocks.block_at(r, 1))
  eq({ name = "A", first = 2, last = 4 }, blocks.block_at(r, 3))
  eq({ name = "A", first = 2, last = 4 }, blocks.block_at(r, 4))
  eq(nil, blocks.block_at(r, 5))
  eq({ name = "B", first = 6 }, blocks.block_at(r, 7))
end)

test("塊：カーソルの {名前}", function()
  local r = parse.parse({ "{A} と {B}" }, cfg)[1]
  eq("A", blocks.ref_at(r, 0).name)
  eq("B", blocks.ref_at(r, #"{A} と {").name)
  eq("A", blocks.ref_at(r, 4).name) -- 塊の外なら最初の塊
end)
