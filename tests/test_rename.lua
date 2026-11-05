-- 古い名前（daihon・v0.1.0）の設定がそのまま動くこと
local config = require("4iii.config")

test("古い名前：require('daihon') は 4iii と同じ物", function()
  eq(true, require("daihon") == require("4iii"))
end)

test("古い名前：daihon.lua しか無い作品フォルダでも設定を見つける", function()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir .. "/sub", "p")
  vim.fn.writefile({ "return {}" }, dir .. "/daihon.lua")
  local found = vim.fs.find(config.FILES, { upward = true, path = dir .. "/sub", type = "file" })[1]
  eq(dir .. "/daihon.lua", found and vim.fs.normalize(found))
  vim.fn.delete(dir, "rf")
end)

test("古い名前：:hi DaihonShiji の上書きが 4iiiShiji にも効く", function()
  require("4iii.view").define_highlights()
  eq("DaihonShiji", vim.api.nvim_get_hl(0, { name = "4iiiShiji" }).link)
  eq("Comment", vim.api.nvim_get_hl(0, { name = "DaihonShiji" }).link)
end)
