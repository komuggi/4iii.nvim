-- 設定：既定値・重ね合わせ・確認・作品フォルダの 4iii.lua の読み込み
local M = {}

M.FILE = "4iii.lua"
-- shortcut: 古い daihon.lua も読む（v0.1.0 の作品フォルダのため）・次の大きい版で外す
M.FILES = { M.FILE, "daihon.lua" }

M.defaults = {
  mode = "solo", -- "solo"（1人・セリフは直打ち）／"multi"（複数人）
  multi = { style = "kagi" }, -- "kagi" = 名前「セリフ」／"colon" = 名前：セリフ
  characters = {},

  -- 行の種類の表。上から順に見て、最初に当てはまったものになる。どれにも当たらない行＝セリフ
  line_types = {
    { name = "メモ", prefix = { "¥", "￥" }, output = false, hl = "4iiiMemo" },
    { name = "指示", prefix = "//", output = true, hl = "4iiiShiji" },
    { name = "位置", prefix = "【", suffix = "】", output = true, hl = "4iiiIchi" },
    { name = "場面", prefix = { "(", "（" }, suffix = { ")", "）" }, output = true, hl = "4iiiBamen" },
  },

  -- 囲い指示。in_types の行の頭に付く。▼ラベル で開いて ▲ラベル で閉じる
  ranges = {
    open = "▼",
    close = "▲",
    in_types = { "指示", "場面" },
    -- ▼ のあとに出す候補：この台本で使ったラベル・位置×距離・そのほかの言葉
    position = { "前", "右前", "左前", "右", "左" },
    distance = { "遠", "中", "近", "密" },
    sep = "・",
    words = {}, -- 例 { "ささやき", "有声音", "無声音" }
    -- 早く出す・見やすくする（どれも false で止められる）
    auto_close = true, -- ▼ラベル で改行すると、下に ▲ラベル を入れる
    brackets = true, -- 行の頭の [[ ]]（「「 」」）を ▼ ▲ にする
    guides = true, -- 範囲の中の行の左に縦の線（画面だけ）
  },

  -- 見出し。count = true の見出しは、次の同じか上の見出しまでを数える
  headings = {
    { level = 1, prefix = "# " },
    { level = 2, prefix = "## ", count = true, show = "%s : %s文字" },
  },

  count = {
    include = { "セリフ" }, -- ト書きも数えるなら { "セリフ", "指示", "場面" }
    ignore_chars = "", -- 数えない記号。空白・改行はいつも数えない
    long_line = 30, -- これより長いセリフに印（一息で読めるのは 20〜30文字）。false で付けない
  },

  -- 候補に出す言葉（この台本で使った言葉も、あとに続けて出す）
  words = {
    se = {}, -- 「// SE : 」のあとに出す。例 { "衣擦れ", "足音", "ドアが開く" }
    shiji = {}, -- 指示の行で <C-x><C-o> を押すと出す。例 { "耳元で", "吐息まじりに" }
  },

  -- 日本語入力のまま打った記号（／／ ＃ ｛｝ など）を、記号として使う場所でだけ半角にする
  hankaku = true,

  parts_dir = "parts",

  -- 文字数をいつも出す場所："winbar"（ウィンドウの上の帯）／"float"（右上の小窓）／"statusline"（下の帯・lualine などに自分で足す）／false
  show_count = "winbar",

  -- キー（台本のバッファだけ）。false にすると付けない
  keys = {
    toggle = "<localleader>b", -- 塊を開く／閉じる
    pick = "<localleader>p", -- 塊の一覧から差し込む
    hover = "K", -- 塊の中身を見る
    range_open = "<localleader>[", -- 下に ▼ の行を作る。行を選んで押すと ▼〜▲ で囲む
    range_close = "<localleader>]", -- 下に ▲ の行を作る
  },

  export = {
    dir = "out", -- 書き出し先（作品フォルダの中）
    pdf = {
      vertical = true, -- 縦書き
      both = true, -- ト書きあり／なしの2つを出す（md・docx も）
      size = "A4 landscape",
      margin = "20mm",
      font = '"BIZ UDPMincho", "BIZ UDP明朝 Medium", "Hiragino Mincho ProN", "Yu Mincho", "Noto Serif JP", serif',
      font_size = "12pt",
      line_height = 1.8,
      page_number = true,
      new_page = 2, -- この段の見出しで改ページ（false で改ページしない）
      serifu_indent = "3em", -- セリフの字下げ（ト書きは行の頭）
      vertical_marks = { open = "◀", close = "▶" }, -- 縦書きで ▼▲ を置き換える記号（false でそのまま）
      css = nil, -- 自分の CSS（作品フォルダからの場所）。既定の見た目のあとに読む
      command = nil, -- PDF を作るコマンド。nil なら vivliostyle
    },
  },
}

local function is_list(t)
  return type(t) == "table" and vim.islist(t) and #t > 0
end

--- base に over を重ねる。表（辞書）は中まで重ね、リストは丸ごと置き換える
function M.merge(base, over)
  if over == nil then
    return vim.deepcopy(base)
  end
  if type(base) ~= "table" or type(over) ~= "table" or is_list(base) or is_list(over) then
    return vim.deepcopy(over)
  end
  local out = vim.deepcopy(base)
  for k, v in pairs(over) do
    out[k] = M.merge(base[k], v)
  end
  return out
end

--- 設定を確かめる。正しければ true、だめなら false とわけを返す
function M.validate(cfg)
  if cfg.mode ~= "solo" and cfg.mode ~= "multi" then
    return false, ('mode は "solo" か "multi" です（今は %s）'):format(vim.inspect(cfg.mode))
  end
  local style = cfg.multi and cfg.multi.style
  if style ~= "kagi" and style ~= "colon" then
    return false, ('multi.style は "kagi" か "colon" です（今は %s）'):format(vim.inspect(style))
  end
  if not vim.tbl_contains({ "winbar", "float", "statusline", false }, cfg.show_count) then
    return false,
      ('show_count は "winbar"・"float"・"statusline"・false のどれかです（今は %s）'):format(
        vim.inspect(cfg.show_count)
      )
  end
  if type(cfg.line_types) ~= "table" then
    return false, "line_types は表で書いてください"
  end
  for i, lt in ipairs(cfg.line_types) do
    if type(lt.name) ~= "string" or lt.name == "" then
      return false, ("line_types の %d 番目に name がありません"):format(i)
    end
    if lt.name == "セリフ" then
      return false,
        "line_types に「セリフ」は使えません（どれにも当たらない行がセリフです）"
    end
    if lt.prefix == nil or lt.prefix == "" then
      return false, ("line_types の「%s」に prefix がありません"):format(lt.name)
    end
  end
  for i, h in ipairs(cfg.headings or {}) do
    if type(h.level) ~= "number" or h.prefix == nil or h.prefix == "" then
      return false, ("headings の %d 番目には level と prefix が要ります"):format(i)
    end
  end
  for _, key in ipairs({ "parts_dir", "export.dir", "export.pdf.css" }) do
    local v = vim.tbl_get(cfg, unpack(vim.split(key, ".", { plain = true })))
    if v ~= nil and not M.inside(v) then
      return false,
        ("%s は作品フォルダの中の場所にしてください（/ や ~ で始めない・.. を使わない）：%s"):format(
          key,
          tostring(v)
        )
    end
  end
  return true
end

--- 作品フォルダの中を指す相対の場所か
function M.inside(path)
  if type(path) ~= "string" or path == "" or path:find("^[/~\\]") or path:find("^%a:") then
    return false
  end
  for part in path:gmatch("[^/\\]+") do
    if part == ".." then
      return false
    end
  end
  return true
end

-- 作品ごとの 4iii.lua では変えられない設定（自分の nvim の設定でだけ変える）
M.GLOBAL_ONLY = { { "export", "pdf", "command" } }

--- 作品ごとの設定から GLOBAL_ONLY を取り除く。取り除いた名前のリストを返す
function M.strip_global_only(project)
  local removed = {}
  for _, path in ipairs(M.GLOBAL_ONLY) do
    local parent = project
    for i = 1, #path - 1 do
      parent = type(parent) == "table" and parent[path[i]] or nil
    end
    if type(parent) == "table" and parent[path[#path]] ~= nil then
      parent[path[#path]] = nil
      removed[#removed + 1] = table.concat(path, ".")
    end
  end
  return removed
end

-- 4iii.lua の中で使える文字列の操作（rep など、大きな文字列を作れるものは外す）
local SAFE_STRING = {}
for _, name in ipairs({
  "byte",
  "char",
  "find",
  "format",
  "gmatch",
  "gsub",
  "len",
  "lower",
  "match",
  "reverse",
  "sub",
  "upper",
}) do
  SAFE_STRING[name] = string[name]
end

local MAX_STEPS = 1e6 -- 実行の長さの上限
local MAX_MEMORY_KB = 64 * 1024 -- 増えてよいメモリの上限

--- 設定ファイルの中身を、何にも触れない空の環境で実行して表を受け取る
--- できるのは表を作って返すことだけ（nvim・ファイル・コマンドには触れない。長すぎる・大きすぎるときは止める）
function M.run_sandboxed(src, name)
  local chunk, err = loadstring(src, "@" .. name)
  if not chunk then
    return nil, err
  end
  setfenv(chunk, {})
  if jit then
    jit.off(chunk, true) -- 上限の見張りが効くように、速くする仕組みを切る
  end

  local string_mt = getmetatable("")
  local saved_index = string_mt.__index
  local base_kb = collectgarbage("count")
  local steps = 0
  string_mt.__index = SAFE_STRING
  local function stop(msg)
    debug.sethook() -- 先に見張りを外す（外さないと、止めたあとの1手でもまた止めてしまう）
    error(msg, 3)
  end
  debug.sethook(function()
    steps = steps + 1
    if steps > MAX_STEPS then
      stop("長すぎるので止めました")
    end
    if collectgarbage("count") - base_kb > MAX_MEMORY_KB then
      stop("大きすぎるので止めました")
    end
  end, "", 1)
  local ok, res = pcall(chunk)
  debug.sethook()
  string_mt.__index = saved_index

  if not ok then
    return nil, tostring(res)
  end
  if type(res) ~= "table" then
    return nil, name .. " は表（return { ... }）を返してください"
  end
  return res
end

--- 作品フォルダの 4iii.lua を読む（run_sandboxed で読むので、信頼の確認は要らない）
function M.read_project(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return nil, path .. " を読めませんでした"
  end
  local res, err = M.run_sandboxed(table.concat(lines, "\n"), path)
  if not res then
    return nil, err
  end
  local removed = M.strip_global_only(res)
  if #removed > 0 then
    return res,
      ("%s は自分の nvim の設定でだけ変えられます（%s では無視しました）"):format(
        table.concat(removed, "、"),
        M.FILE
      )
  end
  return res
end

return M
