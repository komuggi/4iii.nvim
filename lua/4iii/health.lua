-- :checkhealth 4iii — 使う前のつまずきを1画面で確かめる
local M = {}

local h = vim.health

local function has_font(name)
  if vim.fn.executable("fc-list") == 1 then
    local out = vim.fn.system({ "fc-list", ":family" })
    return out:find(name, 1, true) ~= nil
  end
  for _, dir in ipairs({ "~/Library/Fonts", "/Library/Fonts", "~/.local/share/fonts", "/usr/share/fonts" }) do
    if #vim.fn.globpath(vim.fn.expand(dir), "**/*BIZUDPMincho*", false, true) > 0 then
      return true
    end
  end
  return nil -- 確かめられない
end

function M.check()
  h.start("4iii：nvim")
  if vim.fn.has("nvim-0.10") == 1 then
    h.ok("Neovim " .. tostring(vim.version()))
  else
    h.error("Neovim 0.10 以上が要ります（今は " .. tostring(vim.version()) .. "）")
  end

  h.start("4iii：PDF の書き出し")
  local core = require("4iii")
  local st = core.last_buf and core.state(core.last_buf)
  local cmd = st and st.cfg.export.pdf.command
  if cmd then
    h.ok("PDF を作るコマンド（setup で指定）：" .. table.concat(cmd, " "))
  elseif vim.fn.executable("vivliostyle") == 1 then
    h.ok("vivliostyle が入っています")
  else
    h.warn("vivliostyle が入っていません。:4i pdf を使うなら入れてください", {
      "ターミナルで：npm install -g @vivliostyle/cli",
      vim.fn.executable("npm") == 0 and "npm もないので、先に Node.js を入れてください" or nil,
    })
  end
  local font = has_font("BIZ UDPMincho")
  if font then
    h.ok("BIZ UDP明朝が入っています")
  elseif font == false then
    h.info(
      "BIZ UDP明朝が入っていません。PDF はヒラギノ明朝などで出ます（入れると自動で使います）"
    )
  else
    h.info("フォントは確かめられませんでした")
  end

  h.start("4iii：開いている台本")
  if not st then
    h.info(
      "台本（4iii.lua がある作品フォルダの .txt）を開いてから :checkhealth 4iii を打つと、作品の設定も確かめます"
    )
    return
  end
  h.ok("作品フォルダ：" .. vim.fn.fnamemodify(st.root, ":~")) -- ユーザー名を出さない
  if st.config_warning then
    h.warn(st.config_warning)
  else
    h.ok("4iii.lua を読めました")
  end
  local parts = vim.fs.joinpath(st.root, st.cfg.parts_dir)
  local n = #vim.fn.globpath(parts, "*.txt", false, true)
  h.ok(("塊：%s/ に %d 個"):format(st.cfg.parts_dir, n))
  h.ok("文字数の表示：" .. tostring(st.cfg.show_count))

  local snacks = pcall(require, "snacks")
  if snacks then
    h.ok("snacks.nvim があるので、:4i pick で塊の中身を横に出します")
  else
    h.info("snacks.nvim がないので、:4i pick は1行目つきの一覧になります")
  end
end

return M
