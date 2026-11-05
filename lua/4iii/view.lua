-- 画面への表示：色分け・見出しの文字数・▼▲ などの警告
local count = require("4iii.count")

local M = {}

M.ns = vim.api.nvim_create_namespace("4iii")
M.ns_diag = vim.api.nvim_create_namespace("4iii_diag")

-- 色は既存の色の名前につなぐ。自分で変えるときは :hi 4iiiShiji guifg=... のように上書きする
local LINKS = {
  Heading = "Title",
  Shiji = "Comment",
  Ichi = "Type",
  Bamen = "Special",
  Memo = "NonText",
  Range = "Keyword",
  Speaker = "Identifier",
  Block = "Constant",
  Count = "Comment",
  -- 範囲の縦の線（ラベルごとに色を変える）
  Guide1 = "DiagnosticInfo",
  Guide2 = "DiagnosticHint",
  Guide3 = "DiagnosticOk",
  Guide4 = "DiagnosticWarn",
  Guide5 = "Function",
  Guide6 = "Constant",
}

--- ラベルから線の色を決める（同じラベルはいつも同じ色）
local function guide_hl(key)
  local n = 0
  for i = 1, #key do
    n = n + key:byte(i)
  end
  return "4iiiGuide" .. (n % 6 + 1)
end

function M.define_highlights()
  for name, link in pairs(LINKS) do
    -- shortcut: 4iii* → Daihon* → 元の色。v0.1.0 の :hi DaihonShiji の上書きを効かせるため・次の大きい版で Daihon* を外す
    vim.api.nvim_set_hl(0, "Daihon" .. name, { link = link, default = true })
    vim.api.nvim_set_hl(0, "4iii" .. name, { link = "Daihon" .. name, default = true })
  end
end

local function mark(buf, row, s, e, group, priority)
  vim.api.nvim_buf_set_extmark(buf, M.ns, row, s, {
    end_row = row,
    end_col = e,
    hl_group = group,
    priority = priority or 100,
  })
end

--- 1行ずつ色と文字数を付け直す
function M.render(buf, records, summary, issues)
  vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
  for _, r in ipairs(records) do
    local row, len = r.lnum - 1, #r.text
    if r.kind == "見出し" then
      mark(buf, row, 0, len, "4iiiHeading")
      local n = summary.headings[r.lnum]
      if n then
        vim.api.nvim_buf_set_extmark(buf, M.ns, row, 0, {
          virt_text = { { "  " .. count.format(n) .. "文字", "4iiiCount" } },
          virt_text_pos = "eol",
        })
      end
    elseif r.kind == "塊開始" or r.kind == "塊終了" then
      mark(buf, row, 0, len, "4iiiBlock")
      if summary.new_blocks and summary.new_blocks[r.lnum] then
        vim.api.nvim_buf_set_extmark(buf, M.ns, row, 0, {
          virt_text = { { "  新しい塊（保存すると作ります）", "4iiiCount" } },
          virt_text_pos = "eol",
        })
      end
    elseif r.kind == "範囲" then
      mark(buf, row, 0, len, "4iiiRange")
    elseif r.type then
      mark(buf, row, 0, len, r.type.hl or "4iiiShiji")
      if r.range then
        mark(buf, row, r.range.col, len, "4iiiRange", 110)
      end
    elseif r.speaker_col then
      mark(buf, row, r.speaker_col[1], r.speaker_col[2], "4iiiSpeaker")
    end
    for _, ref in ipairs(r.refs or {}) do
      mark(buf, row, ref.s - 1, ref.e, "4iiiBlock", 120)
    end
    local depth = summary.depths and summary.depths[r.lnum]
    if depth then
      local chunks = {}
      for _, o in ipairs(depth) do
        chunks[#chunks + 1] = { "│ ", guide_hl(o.key) }
      end
      vim.api.nvim_buf_set_extmark(buf, M.ns, row, 0, { virt_text = chunks, virt_text_pos = "inline", priority = 50 })
    end
  end

  local diags = {}
  for _, i in ipairs(issues) do
    diags[#diags + 1] = {
      lnum = i.lnum - 1,
      col = i.col or 0,
      end_col = i.end_col,
      severity = i.hint and vim.diagnostic.severity.HINT
        or i.warn and vim.diagnostic.severity.WARN
        or vim.diagnostic.severity.ERROR,
      message = i.msg,
      source = "4iii",
    }
  end
  vim.diagnostic.set(M.ns_diag, buf, diags)
end

return M
