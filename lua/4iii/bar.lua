-- 文字数をいつも出す：ウィンドウの上の帯（winbar）か、右上の小窓（float）
local M = {}

local WINBAR = "%{%v:lua.require'4iii'.winbar()%}"
local floats = {} -- win → { win, buf }

--- このウィンドウだけの winbar（:setlocal）
local function set_winbar(win, value)
  vim.api.nvim_set_option_value("winbar", value, { scope = "local", win = win })
end

local function close_float(win)
  local f = floats[win]
  if f and vim.api.nvim_win_is_valid(f.win) then
    vim.api.nvim_win_close(f.win, true)
  end
  floats[win] = nil
end

--- 右上の小窓を出す（なければ作る）
local function show_float(win, text)
  local width = vim.api.nvim_strwidth(text)
  local opts = {
    relative = "win",
    win = win,
    anchor = "NE",
    row = 0,
    col = vim.api.nvim_win_get_width(win),
    width = math.max(width, 1),
    height = 1,
    focusable = false,
    style = "minimal",
    zindex = 20,
  }
  local f = floats[win]
  if not (f and vim.api.nvim_win_is_valid(f.win)) then
    local fbuf = vim.api.nvim_create_buf(false, true)
    opts.noautocmd = true
    f = { buf = fbuf, win = vim.api.nvim_open_win(fbuf, false, opts) }
    vim.wo[f.win].winhighlight = "Normal:4iiiCount"
    floats[win] = f
  else
    vim.api.nvim_win_set_config(f.win, opts)
  end
  vim.api.nvim_buf_set_lines(f.buf, 0, -1, false, { text })
end

--- 台本のウィンドウに表示を付ける／付け直す（where = cfg.show_count、text = 出す文）
function M.update(win, where, text)
  -- 前に別の場所で出していたら外す
  if where ~= "winbar" and vim.wo[win].winbar == WINBAR then
    set_winbar(win, "")
  end
  if where ~= "float" then
    close_float(win)
  end
  if where == "winbar" then
    if vim.wo[win].winbar ~= WINBAR then
      set_winbar(win, WINBAR)
    end
    vim.api.nvim__redraw({ win = win, winbar = true })
  elseif where == "float" then
    show_float(win, text)
  end
end

--- 台本でないものがウィンドウに来たら外す
function M.clear(win)
  if vim.api.nvim_win_is_valid(win) and vim.wo[win].winbar == WINBAR then
    set_winbar(win, "")
  end
  close_float(win)
end

M.close_float = close_float

return M
