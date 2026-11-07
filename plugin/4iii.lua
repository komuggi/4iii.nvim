if vim.g.loaded_4iii then
  return
end
vim.g.loaded_4iii = true

local group = vim.api.nvim_create_augroup("4iii", { clear = true })

require("4iii.view").define_highlights()
vim.api.nvim_create_autocmd("ColorScheme", {
  group = group,
  callback = function()
    require("4iii.view").define_highlights()
  end,
})

vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
  group = group,
  pattern = "*.txt",
  callback = function(ev)
    require("4iii").attach(ev.buf)
  end,
})

vim.api.nvim_create_autocmd("BufWritePost", {
  group = group,
  pattern = { "4iii.lua", "daihon.lua" },
  callback = function(ev)
    require("4iii").reload_config(ev.match)
  end,
})

-- 文字数の表示：ウィンドウに来たバッファに合わせて付ける／外す
vim.api.nvim_create_autocmd("BufWinEnter", {
  group = group,
  callback = function(ev)
    require("4iii").on_win_enter(vim.api.nvim_get_current_win(), ev.buf)
  end,
})
vim.api.nvim_create_autocmd("WinClosed", {
  group = group,
  callback = function(ev)
    require("4iii").close_bar(tonumber(ev.match))
  end,
})
vim.api.nvim_create_autocmd("WinResized", {
  group = group,
  callback = function()
    for _, win in ipairs(vim.v.event.windows or {}) do
      if vim.api.nvim_win_is_valid(win) then
        require("4iii").on_win_enter(win, vim.api.nvim_win_get_buf(win))
      end
    end
  end,
})

-- :Dh pdf / html / md / docx / count / pick / toggle
vim.api.nvim_create_user_command("Dh", function(o)
  require("4iii").command(o.args)
end, {
  nargs = 1,
  complete = function(lead)
    local names = vim.tbl_keys(require("4iii").commands)
    table.sort(names)
    return vim.tbl_filter(function(n)
      return n:find(lead, 1, true) == 1
    end, names)
  end,
  desc = "4iii：pdf / html / md / docx / count / pick / toggle",
})

-- :4i で打つ（nvim のコマンドは大文字始まりの決まりなので、行の頭の 4i だけ Dh に置き換える）
-- shortcut: :dh は v0.1.0 の打ち方のため残す・次の大きい版で外す
for _, lhs in ipairs({ "4i", "dh" }) do
  vim.keymap.set("ca", lhs, function()
    return (vim.fn.getcmdtype() == ":" and vim.fn.getcmdline() == lhs) and "Dh" or lhs
  end, { expr = true, desc = "4iii: :" .. lhs .. " → :Dh" })
end
