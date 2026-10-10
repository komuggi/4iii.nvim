if vim.g.loaded_daihon then
  return
end
vim.g.loaded_daihon = true

local group = vim.api.nvim_create_augroup("daihon", { clear = true })

require("daihon.view").define_highlights()
vim.api.nvim_create_autocmd("ColorScheme", {
  group = group,
  callback = function()
    require("daihon.view").define_highlights()
  end,
})

vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
  group = group,
  pattern = "*.txt",
  callback = function(ev)
    require("daihon").attach(ev.buf)
  end,
})

vim.api.nvim_create_autocmd("BufWritePost", {
  group = group,
  pattern = "daihon.lua",
  callback = function(ev)
    require("daihon").reload_config(ev.match)
  end,
})

-- 文字数の表示：ウィンドウに来たバッファに合わせて付ける／外す
vim.api.nvim_create_autocmd("BufWinEnter", {
  group = group,
  callback = function(ev)
    require("daihon").on_win_enter(vim.api.nvim_get_current_win(), ev.buf)
  end,
})
vim.api.nvim_create_autocmd("WinClosed", {
  group = group,
  callback = function(ev)
    require("daihon").close_bar(tonumber(ev.match))
  end,
})
vim.api.nvim_create_autocmd("WinResized", {
  group = group,
  callback = function()
    for _, win in ipairs(vim.v.event.windows or {}) do
      if vim.api.nvim_win_is_valid(win) then
        require("daihon").on_win_enter(win, vim.api.nvim_win_get_buf(win))
      end
    end
  end,
})

-- :Dh pdf / html / md / docx / count / pick / toggle
vim.api.nvim_create_user_command("Dh", function(o)
  require("daihon").command(o.args)
end, {
  nargs = 1,
  complete = function(lead)
    local names = vim.tbl_keys(require("daihon").commands)
    table.sort(names)
    return vim.tbl_filter(function(n)
      return n:find(lead, 1, true) == 1
    end, names)
  end,
  desc = "daihon：pdf / html / md / docx / count / pick / toggle",
})

-- 小文字の :dh でも打てるように（nvim のコマンドは大文字始まりの決まりなので、行の頭の dh だけ Dh に置き換える）
vim.keymap.set("ca", "dh", function()
  return (vim.fn.getcmdtype() == ":" and vim.fn.getcmdline() == "dh") and "Dh" or "dh"
end, { expr = true, desc = "daihon: :dh → :Dh" })
