-- 正解の HTML を、元の daihon（Lua）で作る。daihon の中は読むだけ
-- 使い方：nvim --headless -l test/make_expected.lua <daihon のフォルダ> <ケースのフォルダ>...
-- ケースのフォルダ：台本の .txt を1つ・daihon.lua か daihon.json・parts/（あれば）
-- 書く物：<ケース>/expected/<名前>_ト書きあり.html（と _ト書きなし.html）・missing.json
-- daihon.lua があって daihon.json が無ければ、daihon.json も作る（作り直すときは daihon.json を 99-trash へ）
-- .txt の無いフォルダは飛ばす
local daihon_dir = assert(arg[1], "daihon のフォルダを渡してください")
package.path = daihon_dir .. "/lua/?.lua;" .. daihon_dir .. "/lua/?/init.lua;" .. package.path

local config = require("daihon.config")
local parse = require("daihon.parse")
local count = require("daihon.count")
local export = require("daihon.export")

local function write(path, data)
  local f = assert(io.open(path, "wb"))
  f:write(data)
  f:close()
end

local function find_txt(dir)
  local txt
  for name, kind in vim.fs.dir(dir) do
    if kind == "file" and name:sub(-4) == ".txt" then
      assert(not txt, dir .. " に .txt が2つあります")
      txt = name
    end
  end
  return txt
end

for i = 2, #arg do
  local dir = vim.fs.normalize(vim.fn.fnamemodify(arg[i], ":p"))
  local txt = find_txt(dir)
  if txt then
    local project
    local lua_path = vim.fs.joinpath(dir, "daihon.lua")
    if vim.fn.filereadable(lua_path) == 1 then
      project = assert(config.read_project(lua_path))
      if vim.fn.filereadable(vim.fs.joinpath(dir, "daihon.json")) == 0 then
        write(vim.fs.joinpath(dir, "daihon.json"), vim.json.encode(project))
      end
    else
      project = vim.json.decode(table.concat(vim.fn.readfile(vim.fs.joinpath(dir, "daihon.json")), "\n"))
    end
    local cfg = config.merge(config.defaults, project)
    assert(config.validate(cfg))

    local lines = vim.fn.readfile(vim.fs.joinpath(dir, txt))
    local get_part = function(n)
      local path = vim.fs.joinpath(dir, cfg.parts_dir, n .. ".txt")
      if vim.fn.filereadable(path) == 1 then
        return vim.fn.readfile(path)
      end
    end
    local css
    if cfg.export.pdf.css then
      css = table.concat(vim.fn.readfile(vim.fs.joinpath(dir, cfg.export.pdf.css)), "\n")
    end

    local records = parse.parse(lines, cfg)
    local summary = count.summary(records, count.context(cfg, get_part))
    local out = vim.fs.joinpath(dir, "expected")
    vim.fn.mkdir(out, "p")
    local base = txt:sub(1, -5)
    local variants = { { "ト書きあり", true } }
    if cfg.export.pdf.both then
      variants[#variants + 1] = { "ト書きなし", false }
    end
    local missing_all = {}
    for _, v in ipairs(variants) do
      local name = base .. "_" .. v[1]
      local html, missing =
        export.build(records, cfg, { togaki = v[2], title = name, css = css, summary = summary, get_part = get_part })
      for _, m in ipairs(missing) do
        missing_all[m] = true
      end
      write(vim.fs.joinpath(out, name .. ".html"), html)
    end
    local names = vim.tbl_keys(missing_all)
    table.sort(names)
    write(vim.fs.joinpath(out, "missing.json"), vim.json.encode(names))
    io.stdout:write(dir .. "\n")
  end
end
