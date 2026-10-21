# daihon-pdf

音声作品の台本（.txt）を、縦書きの HTML（ト書きあり／なし）にして PDF にします。
[daihon](https://github.com/komuggi/daihon)（nvim のプラグイン）の「台本 → 縦書きの HTML」の所を、nvim なしで動く JavaScript にした物です。書き方・設定・出てくる HTML は daihon と同じです。

## ページ（Google ドキュメントから貼って PDF に）

```sh
python3 -m http.server   # このフォルダで打つ
```

ブラウザで http://localhost:8000/web/ を開き、左に台本を貼ります。右に縦書きで出ます。

- 「ト書きあり／なし」で切り替え、「印刷して PDF に」→ 印刷の画面で「PDF に保存」
- 貼るとき、日本語入力のままの記号（行の頭の `／／` `＃` `（` `￥`、`｛｝` など）は daihon で打ったときと同じに半角にします
- 設定は「設定」の欄に daihon.json の形で書きます。塊（`{名前}`）は「塊を読む」で parts/ の .txt を選びます
- 何も外へ送りません（書いた物はこのブラウザの中にだけ残ります）

## CLI

```sh
node bin/daihon-pdf.js 台本.txt [--config daihon.json] [--out out/] [--no-pdf]
```

ト書きあり／なしの HTML を書き、`vivliostyle` があれば PDF も作ります（無ければ HTML だけ）。
`--config` が無ければ、台本と同じフォルダの `daihon.json` を読みます。塊は設定のあるフォルダの `parts/` から読みます。

## 設定（daihon.json）

daihon の `daihon.lua` と同じ意味・同じ既定値を JSON で書きます。例：`test/fixtures/sample/daihon.json`。
nvim の画面だけの設定（keys・show_count など）は読んでも使いません。`export.pdf.command` は使いません。

## 部品として使う

```js
import { makeConfig, render } from "./src/index.js";
const { outputs, missing } = render(text, makeConfig({ mode: "multi" }), { name: "台本", getPart });
// outputs = [{ name: "台本_ト書きあり", togaki: true, html }, { name: "台本_ト書きなし", ... }]
```

## テスト

```sh
node --test
```

`test/fixtures/` の HTML は、元の daihon（Lua）が作った物です（`test/make_expected.lua`・daihon のコミットは `DAIHON_COMMIT`）。daihon を直したら作り直して、ここも同じ結果になるかを確かめます。

```sh
nvim --headless -l test/make_expected.lua ~/tools/daihon test/fixtures/*/
```
