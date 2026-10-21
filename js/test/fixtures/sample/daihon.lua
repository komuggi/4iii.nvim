-- 作品ごとの設定。書いたところだけ、全体の設定を上書きします（return {} の1行でもかまいません）
-- 例として、よく変える設定を並べました。値を変えて保存すると、開いている台本がすぐ変わります
-- ★ の所だけ既定から変えています。ほかは既定の値のままです（全部の設定は :h daihon-config）
return {
  mode = "solo", -- 1人の台本。"multi" にすると 名前「セリフ」 で書けて、名前とかっこは数えない

  -- 行の頭の記号と種類の表。上から順に見て、最初に当てはまったもの。どれにも当たらない行がセリフ
  -- リストは丸ごと置き換わるので、足すときは既定の4つも書きます
  line_types = {
    { name = "メモ", prefix = { "¥", "￥" }, output = false, hl = "DaihonMemo" }, -- output = false で書き出さない
    { name = "指示", prefix = "//", hl = "DaihonShiji" },
    { name = "位置", prefix = "【", suffix = "】", hl = "DaihonIchi" },
    { name = "場面", prefix = { "(", "（" }, suffix = { ")", "）" }, hl = "DaihonBamen" },
    { name = "注意", prefix = "※", hl = "DiagnosticWarn" }, -- ★ 足した種類（hl は色の名前）
  },

  ranges = {
    open = "▼", -- 範囲の始まりの記号
    close = "▲", -- 範囲の終わりの記号
    words = { "ささやき" }, -- ★ ▼ のあとの候補に足す言葉
    auto_close = true, -- ▼ の行で改行すると、下に ▲ を入れる
    brackets = true, -- 行の頭の [[ ]] を ▼ ▲ にする
    guides = true, -- 範囲の中の行の左に縦の線
  },

  count = {
    include = { "セリフ" }, -- 数える種類。ト書きもなら { "セリフ", "指示", "位置", "場面" }
    ignore_chars = "…", -- ★ 数えない記号（既定は ""）。例 "…、。"
    long_line = 30, -- これより長いセリフに知らせ。false で出さない
  },

  words = {
    se = { "ドアが開く", "足音", "衣擦れ" }, -- ★ 「// SE : 」のあとの候補
  },

  show_count = "winbar", -- 文字数を出す場所。"float" で右上の小窓、false で出さない

  export = {
    pdf = {
      vertical = true, -- false で横書き
      both = true, -- false でト書きありの1つだけ
      new_page = 2, -- ## までの見出しで改ページ。false でしない
      serifu_indent = "3em", -- セリフの字下げ
      vertical_marks = { open = "◀", close = "▶" }, -- 縦書きでの ▼ ▲。false でそのまま
    },
  },
}
