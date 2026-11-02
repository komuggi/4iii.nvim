-- daihon：音声作品の台本を書くための nvim プラグイン
local config = require("daihon.config")
local parse = require("daihon.parse")
local count = require("daihon.count")
local view = require("daihon.view")
local blocks = require("daihon.blocks")
local export = require("daihon.export")
local bar = require("daihon.bar")
local complete = require("daihon.complete")
local hankaku = require("daihon.hankaku")

local M = {}

local global_opts = {}
local set_keys
local bufs = {} -- buf → { root, cfg, config_path, last }
local timers = {}

--- 全体の設定。nvim の設定から require("daihon").setup({ ... }) で呼ぶ
function M.setup(opts)
  global_opts = opts or {}
  if global_opts.lower_dh == false then
    pcall(vim.keymap.del, "ca", "dh")
  end
  global_opts.lower_dh = nil
  view.define_highlights()
  for buf in pairs(bufs) do
    M.attach(buf, true)
  end
end

local read_part = blocks.read_part

local function context(st, include)
  return count.context(st.cfg, function(name)
    return read_part(st, name)
  end, include)
end

--- 色・文字数・警告を付け直す
function M.refresh(buf)
  local st = bufs[buf]
  if not st or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local records = parse.parse(lines, st.cfg)
  local ctx = context(st)
  local summary = count.summary(records, ctx)
  local issues = parse.check_ranges(records, st.cfg)
  for _, r in ipairs(records) do
    if r.output then
      for _, ref in ipairs(r.refs or {}) do
        if ref.name:sub(1, 1) == "@" and not export.BUILTINS[ref.name] then
          issues[#issues + 1] = {
            lnum = r.lnum,
            col = ref.s - 1,
            end_col = ref.e,
            warn = true,
            msg = "知らない組み込みの塊です：" .. ref.name,
          }
        elseif ref.name:sub(1, 1) ~= "@" and not ctx.has_part(ref.name) then
          issues[#issues + 1] = {
            lnum = r.lnum,
            col = ref.s - 1,
            end_col = ref.e,
            warn = true,
            msg = ("未登録の塊です：%s（%s/%s.txt がありません）"):format(
              ref.name,
              st.cfg.parts_dir,
              ref.name
            ),
          }
        end
      end
    end
  end
  for _, l in ipairs(count.long_lines(records, ctx, st.cfg.count.long_line)) do
    issues[#issues + 1] = {
      lnum = l.lnum,
      hint = true,
      msg = ("長いセリフです（%d文字）。一息で読めるのは %d文字くらいまで"):format(
        l.n,
        st.cfg.count.long_line
      ),
    }
  end
  if st.cfg.ranges.guides then
    summary.depths = parse.range_depths(records, st.cfg)
  end
  summary.new_blocks = {}
  for _, r in ipairs(records) do
    if r.kind == "塊開始" and not ctx.has_part(r.block_name) then
      summary.new_blocks[r.lnum] = true
    end
  end
  st.last = { records = records, summary = summary }
  view.render(buf, records, summary, issues)
  M.update_bars(buf)
end

local function bar_text(buf, win)
  local st = bufs[buf]
  if not st or not st.last then
    return ""
  end
  local lnum = vim.api.nvim_win_get_cursor(win)[1]
  return count.bar_text(st.last.records, st.last.summary, lnum)
end

--- 台本を出しているウィンドウの文字数の表示を付け直す
function M.update_bars(buf)
  local st = bufs[buf]
  if not st or not st.cfg.show_count then
    return
  end
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    bar.update(win, st.cfg.show_count, bar_text(buf, win))
  end
end

--- ウィンドウに来たバッファに合わせて、文字数の表示を付ける／外す
function M.on_win_enter(win, buf)
  local st = bufs[buf]
  if st and st.cfg.show_count then
    bar.update(win, st.cfg.show_count, bar_text(buf, win))
  else
    bar.clear(win)
  end
end

M.close_bar = bar.close_float

--- winbar から呼ばれる：右寄せの文字数
function M.winbar()
  local win = vim.g.statusline_winid
  if not (win and vim.api.nvim_win_is_valid(win)) then
    win = vim.api.nvim_get_current_win()
  end
  local ok, text = pcall(bar_text, vim.api.nvim_win_get_buf(win), win)
  if not ok then
    return "" -- 帯の計算で失敗しても、画面は壊さない
  end
  return "%=" .. text:gsub("%%", "%%%%") .. " "
end

--- 候補を出す。選ぶまで勝手に入らないよう、そのときだけ completeopt に noselect を足す
local function show_candidates(col, items)
  local co = vim.o.completeopt
  if not (co:find("noselect") or co:find("noinsert")) then
    vim.o.completeopt = co .. ",noselect"
    vim.api.nvim_create_autocmd({ "CompleteDone", "InsertLeave" }, {
      once = true,
      callback = function()
        vim.o.completeopt = co
      end,
    })
  end
  vim.fn.complete(col + 1, items)
end

local function candidates_here(buf, st)
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local before = vim.api.nvim_get_current_line():sub(1, col)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local all = parse.parse(lines, st.cfg)
  local above = vim.list_slice(all, 1, row - 1)
  return complete.at(before, above, st.cfg, all)
end

--- ▼・▲ を打った直後に候補を出す
local function auto_complete(buf)
  local st = bufs[buf]
  if not st or vim.fn.pumvisible() == 1 then
    return
  end
  local c = candidates_here(buf, st)
  if c and c.auto and #c.items > 0 then
    show_candidates(c.col, c.items)
  end
end

--- 行の頭の [[ ]]（「「 」」）を ▼ ▲ にする
local function brackets(st)
  if not st.cfg.ranges.brackets then
    return
  end
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_get_current_line()
  local before = hankaku.brackets(line:sub(1, col), st.cfg.ranges)
  if before then
    vim.api.nvim_set_current_line(before .. line:sub(col + 1))
    vim.api.nvim_win_set_cursor(0, { row, #before })
  end
end

local shapes = {} -- buf → { n = 行の数, row = カーソルの行 }（改行したかを見分ける）

--- ▼ラベル の行で改行したら、下に ▲ラベル を入れる（まだ閉じていなければ）
local function auto_close(buf, st)
  local n = vim.api.nvim_buf_line_count(buf)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local prev = shapes[buf]
  shapes[buf] = { n = n, row = row }
  if not (st.cfg.ranges.auto_close and prev and n == prev.n + 1 and row == prev.row + 1 and row > 1) then
    return
  end
  local records = parse.parse(vim.api.nvim_buf_get_lines(buf, 0, -1, false), st.cfg)
  local r = records[row - 1]
  if not (r.range and r.range.op == "open" and r.range.label ~= "") then
    return
  end
  if parse.has_close_below(vim.list_slice(records, row + 1), r.range.key) then
    return
  end
  vim.api.nvim_buf_set_lines(buf, row, row, false, { parse.close_text(r, st.cfg) })
  shapes[buf] = { n = n + 1, row = row }
end

--- 下に ▼（op = "open"）か ▲（"close"）の行を作って、候補を出す
function M.range_line(op)
  local buf = vim.api.nvim_get_current_buf()
  local st = bufs[buf]
  if not st then
    return
  end
  local mark = op == "open" and st.cfg.ranges.open or st.cfg.ranges.close
  local row = vim.api.nvim_win_get_cursor(0)[1]
  vim.api.nvim_buf_set_lines(buf, row, row, false, { mark })
  vim.api.nvim_win_set_cursor(0, { row + 1, #mark })
  vim.cmd("startinsert!")
  vim.schedule(function()
    auto_complete(buf)
  end)
end

--- 選んだ行を ▼ラベル 〜 ▲ラベル で囲む（ラベルは候補から選ぶか、自分で書く）
function M.wrap()
  local buf = vim.api.nvim_get_current_buf()
  local st = bufs[buf]
  if not st then
    return
  end
  local a, b = vim.fn.line("v"), vim.fn.line(".")
  local first, last = math.min(a, b), math.max(a, b)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)

  local ranges = st.cfg.ranges
  local put = function(label)
    if not label or label == "" then
      return
    end
    vim.api.nvim_buf_set_lines(buf, last, last, false, { ranges.close .. label })
    vim.api.nvim_buf_set_lines(buf, first - 1, first - 1, false, { ranges.open .. label })
  end
  local records = parse.parse(vim.api.nvim_buf_get_lines(buf, 0, -1, false), st.cfg)
  local items = vim.tbl_map(function(it)
    return it.word
  end, complete.open_labels(records, st.cfg))
  local own = "（自分で書く）"
  table.insert(items, 1, own)
  vim.ui.select(items, { prompt = "囲むラベル" }, function(choice)
    if choice == own then
      vim.ui.input({ prompt = "ラベル：" }, put)
    else
      put(choice)
    end
  end)
end

local omni_last
--- <C-x><C-o> で候補を出す（omnifunc）
function M.omnifunc(findstart, base)
  local buf = vim.api.nvim_get_current_buf()
  local st = bufs[buf]
  if findstart == 1 then
    omni_last = st and candidates_here(buf, st) or nil
    return omni_last and omni_last.col or -3
  end
  return omni_last and complete.filter(omni_last.items, base) or {}
end

local function schedule(buf)
  local t = timers[buf]
  if t then
    t:stop()
  else
    t = vim.uv.new_timer()
    timers[buf] = t
  end
  t:start(
    150,
    0,
    vim.schedule_wrap(function()
      M.refresh(buf)
    end)
  )
end

--- 台本のバッファにだけキーを付ける
set_keys = function(buf, keys)
  local function map(lhs, fn, desc, mode)
    if lhs and lhs ~= false and lhs ~= "" then
      vim.keymap.set(mode or "n", lhs, fn, { buffer = buf, desc = "daihon: " .. desc })
    end
  end
  map(keys.toggle, function()
    M.toggle()
  end, "塊を開く／閉じる")
  map(keys.pick, function()
    M.pick()
  end, "塊の一覧から差し込む")
  map(keys.hover, function()
    if not M.hover() and next(vim.lsp.get_clients({ bufnr = buf })) then
      vim.lsp.buf.hover()
    end
  end, "塊の中身を見る")
  map(keys.range_open, function()
    M.range_line("open")
  end, "下に ▼ の行を作る")
  map(keys.range_open, function()
    M.wrap()
  end, "選んだ行を ▼〜▲ で囲む", "x")
  map(keys.range_close, function()
    M.range_line("close")
  end, "下に ▲ の行を作る")
end

local function detach(buf)
  bufs[buf] = nil
  if timers[buf] then
    timers[buf]:stop()
    timers[buf]:close()
    timers[buf] = nil
  end
end

--- 作品フォルダ（daihon.lua がある所）の中の .txt なら台本として扱う
function M.attach(buf, force)
  if bufs[buf] and not force then
    return
  end
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" then
    return
  end
  local found = vim.fs.find(config.FILE, { upward = true, path = vim.fs.dirname(name), type = "file" })[1]
  if not found then
    return
  end

  local project, err = config.read_project(found)
  if err then
    vim.notify("daihon: " .. err, vim.log.levels.WARN)
  end
  M.last_buf = buf
  local cfg = config.merge(config.merge(config.defaults, global_opts), project)
  local ok, verr = config.validate(cfg)
  if not ok then
    vim.notify("daihon: 設定が正しくありません：" .. verr, vim.log.levels.ERROR)
    return
  end

  local first = bufs[buf] == nil
  bufs[buf] = { root = vim.fs.dirname(found), cfg = cfg, config_path = found, config_warning = err }
  vim.b[buf].daihon = true
  vim.bo[buf].omnifunc = "v:lua.require'daihon'.omnifunc"

  if first then
    local group = vim.api.nvim_create_augroup("daihon_buf_" .. buf, { clear = true })
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
      group = group,
      buffer = buf,
      callback = function(ev)
        if ev.event == "TextChangedI" then
          local st = bufs[buf]
          if st then
            brackets(st)
            auto_close(buf, st)
          end
          auto_complete(buf)
        end
        schedule(buf)
      end,
    })
    vim.api.nvim_create_autocmd("BufWritePost", {
      group = group,
      buffer = buf,
      callback = function()
        blocks.create_new_on_save(buf, bufs[buf])
        M.refresh(buf)
      end,
    })
    vim.api.nvim_create_autocmd("InsertEnter", {
      group = group,
      buffer = buf,
      callback = function()
        shapes[buf] = { n = vim.api.nvim_buf_line_count(buf), row = vim.api.nvim_win_get_cursor(0)[1] }
      end,
    })
    vim.api.nvim_create_autocmd("InsertCharPre", {
      group = group,
      buffer = buf,
      callback = function()
        local st = bufs[buf]
        if not (st and st.cfg.hankaku) then
          return
        end
        local col = vim.api.nvim_win_get_cursor(0)[2]
        local half = hankaku.convert(vim.v.char, vim.api.nvim_get_current_line():sub(1, col))
        if half then
          vim.v.char = half
        end
      end,
    })
    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
      group = group,
      buffer = buf,
      callback = function()
        M.update_bars(buf)
      end,
    })
    vim.api.nvim_create_autocmd("BufEnter", {
      group = group,
      buffer = buf,
      callback = function()
        M.last_buf = buf
        M.refresh(buf)
      end,
    })
    vim.api.nvim_create_autocmd({ "BufWipeout" }, {
      group = group,
      buffer = buf,
      callback = function()
        detach(buf)
      end,
    })
  end
  if first then
    set_keys(buf, cfg.keys or {})
  end
  M.refresh(buf)
end

--- daihon.lua を保存したら、その作品の台本を読み直す
function M.reload_config(path)
  path = vim.fs.normalize(path)
  for buf, st in pairs(bufs) do
    if vim.fs.normalize(st.config_path) == path then
      M.attach(buf, true)
    end
  end
end

--- :Dh count — 全体と見出しごとの文字数（セリフだけ／ト書きも）
function M.show_count(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local st = bufs[buf]
  if not st then
    vim.notify(
      "daihon: このファイルは台本として開かれていません（作品フォルダに daihon.lua がありません）"
    )
    return
  end
  local records = parse.parse(vim.api.nvim_buf_get_lines(buf, 0, -1, false), st.cfg)
  local all = {}
  for _, lt in ipairs(st.cfg.line_types) do
    if lt.output ~= false then
      all[#all + 1] = lt.name
    end
  end
  table.insert(all, 1, "セリフ")
  local a = count.summary(records, context(st))
  local b = count.summary(records, context(st, all))

  local out =
    { ("全体  %s文字（ト書きも数えると %s文字）"):format(count.format(a.total), count.format(b.total)) }
  for _, r in ipairs(records) do
    if a.headings[r.lnum] then
      out[#out + 1] = ("%s%s  %s文字（%s）"):format(
        string.rep("  ", r.level - 1),
        r.title,
        count.format(a.headings[r.lnum]),
        count.format(b.headings[r.lnum])
      )
    end
  end
  vim.notify(table.concat(out, "\n"), vim.log.levels.INFO, { title = "daihon" })
end

local function with_state(fn)
  return function(buf)
    buf = buf or vim.api.nvim_get_current_buf()
    local st = bufs[buf]
    if not st then
      vim.notify(
        "daihon: このファイルは台本として開かれていません（作品フォルダに daihon.lua がありません）"
      )
      return false
    end
    return fn(buf, st)
  end
end

M.toggle = with_state(blocks.toggle)
M.pick = with_state(blocks.pick)
M.hover = with_state(blocks.hover)

--- 書き出したものをファイルに書く（バイト列のまま）
local function write_file(path, data)
  local f, err = io.open(path, "wb")
  if not f then
    vim.notify("daihon: 書き出せませんでした：" .. tostring(err), vim.log.levels.ERROR)
    return false
  end
  f:write(data)
  f:close()
  return true
end

--- :Dh pdf / html / md / docx — 台本を書き出す（what = "pdf" | "html" | "md" | "docx"）
function M.export(what, buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local st = bufs[buf]
  if not st then
    vim.notify(
      "daihon: このファイルは台本として開かれていません（作品フォルダに daihon.lua がありません）"
    )
    return
  end
  local cfg, pdf = st.cfg, st.cfg.export.pdf
  local records = parse.parse(vim.api.nvim_buf_get_lines(buf, 0, -1, false), cfg)
  local summary = count.summary(records, context(st))

  local css
  if pdf.css and (what == "pdf" or what == "html") then
    local path = vim.fs.joinpath(st.root, pdf.css)
    if vim.fn.filereadable(path) == 0 then
      vim.notify("daihon: CSS が見つかりません：" .. path, vim.log.levels.ERROR)
      return
    end
    css = table.concat(vim.fn.readfile(path), "\n")
  end

  local cmd = pdf.command
  if what == "pdf" and not cmd then
    if vim.fn.executable("vivliostyle") == 0 then
      vim.notify(
        "daihon: PDF を作るには Vivliostyle が要ります。ターミナルで次を打ってください：\n  npm install -g @vivliostyle/cli",
        vim.log.levels.ERROR
      )
      return
    end
    cmd = { "vivliostyle" }
  end

  local function rel(path)
    return path:sub(#st.root + 2)
  end
  local out_dir = vim.fs.joinpath(st.root, cfg.export.dir)
  vim.fn.mkdir(out_dir, "p")
  local base = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t:r")
  local jobs, missing_all = {}, {}
  local variants = { { "ト書きあり", true } }
  if pdf.both then
    variants[#variants + 1] = { "ト書きなし", false }
  end
  -- PDF は HTML を作ってから Vivliostyle で PDF にする
  local make = ({ md = export.markdown, docx = require("daihon.docx").build })[what] or export.build
  local ext = (what == "md" or what == "docx") and what or "html"

  for _, v in ipairs(variants) do
    local name = base .. "_" .. v[1]
    local data, missing = make(records, cfg, {
      togaki = v[2],
      title = name,
      css = css,
      summary = summary,
      get_part = function(n)
        return read_part(st, n)
      end,
    })
    for _, m in ipairs(missing) do
      missing_all[m] = true
    end
    local path = vim.fs.joinpath(out_dir, name .. "." .. ext)
    if not write_file(path, data) then
      return
    end

    if what == "pdf" then
      jobs[#jobs + 1] = { name = name, html = path, pdf = vim.fs.joinpath(out_dir, name .. ".pdf") }
    else
      vim.notify("daihon: 書き出しました：" .. rel(path))
    end
  end

  if next(missing_all) then
    local names = vim.tbl_keys(missing_all)
    table.sort(names)
    vim.notify(
      "daihon: 未登録の塊はそのまま出しました：" .. table.concat(names, "、"),
      vim.log.levels.WARN
    )
  end

  -- PDF は1つずつ作る（同時に作ると Vivliostyle がぶつかる）
  local function run(i)
    local job = jobs[i]
    if not job then
      return
    end
    vim.notify("daihon: PDF を作っています：" .. job.name)
    local args = vim.list_extend(vim.deepcopy(cmd), { "build", job.html, "-o", job.pdf })
    vim.system(args, { cwd = out_dir, text = true }, function(res)
      vim.schedule(function()
        if res.code == 0 then
          vim.notify("daihon: PDF ができました：" .. rel(job.pdf))
        else
          local err = vim.trim((res.stderr or "") .. (res.stdout or ""))
          vim.notify(
            "daihon: PDF を作れませんでした（" .. job.name .. "）\n" .. err:sub(-800),
            vim.log.levels.ERROR
          )
        end
        run(i + 1)
      end)
    end)
  end
  run(1)
end

--- 台本として開いているバッファの状態（:checkhealth 用）
function M.state(buf)
  return bufs[buf]
end

--- ステータスライン（lualine など）に出す用：「Track 01 おかえり 32文字 ／ 全体 41文字」
function M.status()
  return bar_text(vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win())
end

-- :Dh のやること
M.commands = {
  pdf = function()
    M.export("pdf")
  end,
  html = function()
    M.export("html")
  end,
  md = function()
    M.export("md")
  end,
  docx = function()
    M.export("docx")
  end,
  count = function()
    M.show_count()
  end,
  pick = function()
    M.pick()
  end,
  toggle = function()
    M.toggle()
  end,
}

--- :Dh {やること}
function M.command(arg)
  local fn = M.commands[arg]
  if not fn then
    local names = vim.tbl_keys(M.commands)
    table.sort(names)
    vim.notify(
      "daihon: :Dh のあとに書けるのは " .. table.concat(names, " / ") .. " です",
      vim.log.levels.WARN
    )
    return
  end
  fn()
end

return M
