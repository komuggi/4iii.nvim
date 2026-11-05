-- 塊（{名前}）の操作：開く・閉じる・中身を見る・一覧から差し込む・保存で新しく作る
local parse = require("4iii.parse")
local count = require("4iii.count")

local M = {}

--- 塊の名前に使えるか（ファイル名になるので / や先頭の . はだめ）
function M.valid_name(name)
  return name ~= "" and not name:find("[/\\]") and name:sub(1, 1) ~= "." and #name <= 100
end

--- lnum 行目を囲んでいる {{名前 〜 }} を探す。返す表：{ name, first, last }（last は }} の行。閉じていなければ nil）
function M.block_at(records, lnum)
  local cur
  for _, r in ipairs(records) do
    if r.kind == "塊開始" then
      if cur and cur.first <= lnum and lnum < r.lnum then
        return cur -- 閉じていない塊の中
      end
      cur = { name = r.block_name, first = r.lnum }
    elseif r.kind == "塊終了" and cur then
      cur.last = r.lnum
      if cur.first <= lnum and lnum <= cur.last then
        return cur
      end
      cur = nil
    end
  end
  if cur and cur.first <= lnum then
    return cur
  end
end

--- その行の {名前}。col（0 始まり）が中にある塊、なければ行の最初の塊
function M.ref_at(record, col)
  local refs = record and record.refs or {}
  for _, ref in ipairs(refs) do
    if col and ref.s - 1 <= col and col <= ref.e - 1 then
      return ref
    end
  end
  return refs[1]
end

local function part_path(st, name)
  return vim.fs.joinpath(st.root, st.cfg.parts_dir, name .. ".txt")
end

--- 塊の中身（parts/名前.txt の行）。無い・名前に使えない（../ など parts/ の外を指す）なら nil
function M.read_part(st, name)
  if not M.valid_name(name) then
    return nil
  end
  local path = part_path(st, name)
  if vim.fn.filereadable(path) == 1 then
    return vim.fn.readfile(path)
  end
end
local read_part = M.read_part

local function write_part(st, name, lines)
  local path = part_path(st, name)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  if vim.fn.writefile(lines, path) ~= 0 then
    error(path .. " に書けませんでした")
  end
  return path
end

local function records_of(buf, st)
  return parse.parse(vim.api.nvim_buf_get_lines(buf, 0, -1, false), st.cfg)
end

local function rel(st, path)
  return vim.fs.relpath and vim.fs.relpath(st.root, path) or path
end

--- カーソルの {名前} を開く（1行に {名前} だけのとき）
function M.open(buf, st)
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local r = records_of(buf, st)[row]
  local ref = M.ref_at(r, col)
  if not ref then
    return false
  end
  if parse.trim(r.text) ~= r.text:sub(ref.s, ref.e) then
    vim.notify(
      "4iii: 行の途中の塊は開けません。{" .. ref.name .. "} だけの行にしてください",
      vim.log.levels.WARN
    )
    return true
  end
  local lines = read_part(st, ref.name)
  if not lines then
    vim.notify("4iii: 未登録の塊です：" .. ref.name, vim.log.levels.WARN)
    return true
  end
  local out = { "{{" .. ref.name }
  vim.list_extend(out, lines)
  out[#out + 1] = "}}"
  vim.api.nvim_buf_set_lines(buf, row - 1, row, false, out)
  return true
end

--- カーソルのある {{名前 〜 }} を閉じる。中身が変わっていたら、どこを直すか聞く
function M.close(buf, st)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local b = M.block_at(records_of(buf, st), row)
  if not b then
    return false
  end
  if not b.last then
    vim.notify("4iii: {{" .. b.name .. " を閉じる }} がありません", vim.log.levels.WARN)
    return true
  end
  if not M.valid_name(b.name) then
    vim.notify("4iii: この名前は塊に使えません：" .. b.name, vim.log.levels.WARN)
    return true
  end
  local inner = vim.api.nvim_buf_get_lines(buf, b.first, b.last - 1, false)
  local collapse = function()
    vim.api.nvim_buf_set_lines(buf, b.first - 1, b.last, false, { "{" .. b.name .. "}" })
  end

  local saved = read_part(st, b.name)
  if not saved then
    local path = write_part(st, b.name, inner)
    collapse()
    vim.notify("4iii: 新しい塊を作りました：" .. rel(st, path))
    return true
  end
  if vim.deep_equal(saved, inner) then
    collapse()
    return true
  end

  local here = "この場所だけ（塊と切り離して、普通の文章にする）"
  local both = "元の塊も直す（" .. st.cfg.parts_dir .. "/" .. b.name .. ".txt を書き換える）"
  vim.ui.select(
    { here, both },
    { prompt = "「" .. b.name .. "」の中身が変わっています。どこを直しますか？" },
    function(choice)
      if choice == here then
        vim.api.nvim_buf_set_lines(buf, b.last - 1, b.last, false, {})
        vim.api.nvim_buf_set_lines(buf, b.first - 1, b.first, false, {})
      elseif choice == both then
        write_part(st, b.name, inner)
        collapse()
        vim.notify("4iii: 塊を書き換えました：" .. b.name)
      end
    end
  )
  return true
end

--- 開いていれば閉じる、{名前} の上なら開く
function M.toggle(buf, st)
  if M.close(buf, st) or M.open(buf, st) then
    return
  end
  vim.notify("4iii: カーソルの所に塊がありません")
end

--- K：カーソルの塊の中身と文字数を小窓で出す
function M.hover(buf, st)
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local records = records_of(buf, st)
  local name
  local ref = M.ref_at(records[row], col)
  if ref then
    name = ref.name
  else
    local b = M.block_at(records, row)
    name = b and b.name
  end
  if not name then
    return false
  end
  local lines = read_part(st, name)
  if not lines then
    vim.notify("4iii: 未登録の塊です：" .. name, vim.log.levels.WARN)
    return true
  end
  local ctx = count.context(st.cfg, function(n)
    return read_part(st, n)
  end)
  local title = (" %s · %s文字 "):format(name, count.format(ctx.part_count(name)))
  vim.lsp.util.open_floating_preview(lines, "text", { border = "rounded", title = title, focus_id = "4iii_hover" })
  return true
end

--- 登録済みの塊の一覧（名前順）
function M.list(st)
  local dir = vim.fs.joinpath(st.root, st.cfg.parts_dir)
  local items = {}
  for name, kind in vim.fs.dir(dir) do
    if kind == "file" and name:sub(-4) == ".txt" then
      items[#items + 1] = { name = name:sub(1, -5), path = vim.fs.joinpath(dir, name) }
    end
  end
  table.sort(items, function(a, b)
    return a.name < b.name
  end)
  return items
end

--- 空の行ならその行に、文字がある行ならカーソルの後ろに {名前} を入れる
local function insert_ref(name)
  local ref = "{" .. name .. "}"
  if parse.trim(vim.api.nvim_get_current_line()) == "" then
    vim.api.nvim_set_current_line(ref)
  else
    vim.api.nvim_put({ ref }, "c", true, true)
  end
end

--- 一覧から選んで {名前} を差し込む。snacks.nvim があれば中身を横に出す
function M.pick(buf, st)
  local items = M.list(st)
  if #items == 0 then
    vim.notify(
      "4iii: 塊がまだありません（"
        .. st.cfg.parts_dir
        .. "/ に .txt を置くか、{{名前 〜 }} で作る）"
    )
    return
  end
  local ok, snacks = pcall(require, "snacks")
  if ok and snacks.picker then
    local pitems = {}
    for _, it in ipairs(items) do
      pitems[#pitems + 1] = { text = it.name, file = it.path }
    end
    snacks.picker.pick({
      title = "塊",
      items = pitems,
      format = "text",
      confirm = function(picker, item)
        picker:close()
        if item then
          vim.schedule(function()
            insert_ref(item.text)
          end)
        end
      end,
    })
    return
  end
  vim.ui.select(items, {
    prompt = "塊",
    format_item = function(it)
      local first = (vim.fn.readfile(it.path, "", 1)[1] or "")
      return it.name .. "  │ " .. first
    end,
  }, function(it)
    if it then
      insert_ref(it.name)
    end
  end)
end

--- 保存のとき：まだ登録されていない {{名前 〜 }} を parts/ に作る
function M.create_new_on_save(buf, st)
  local made = {}
  local records = records_of(buf, st)
  for _, r in ipairs(records) do
    if r.kind == "塊開始" then
      local b = M.block_at(records, r.lnum)
      if b and b.last and not M.valid_name(b.name) then
        vim.notify(
          "4iii: この名前は塊に使えないので作りませんでした：" .. b.name,
          vim.log.levels.WARN
        )
      elseif b and b.last and not read_part(st, b.name) then
        local inner = vim.api.nvim_buf_get_lines(buf, b.first, b.last - 1, false)
        made[#made + 1] = rel(st, write_part(st, b.name, inner))
      end
    end
  end
  if #made > 0 then
    vim.notify("4iii: 新しい塊を作りました：" .. table.concat(made, "、"))
  end
end

return M
