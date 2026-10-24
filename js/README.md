# daihon-pdf

音声作品の台本（.txt）を、縦書きの HTML（ト書きあり／なし）にして PDF にします。
[daihon](https://github.com/komuggi/daihon)（nvim のプラグイン）の「台本 → 縦書きの HTML」の所を、nvim なしで動く JavaScript にした物です。書き方・設定・出てくる HTML は daihon と同じです（ルビだけは js 版にしかありません）。

## ページ（Google ドキュメントから貼って PDF に）

```sh
python3 -m http.server   # このフォルダで打つ
```

ブラウザで http://localhost:8000/web/ を開き、左に台本を貼ります。右に縦書きで出ます。

- 上の枠に、行の頭に付けている記号を打ちます（、で区切る）
  - **SE**・**コメント・演技指示**：文字数に入れず、「ト書きあり」の PDF にだけ出します
  - **その他**：セリフにしない行。PDF に出すか出さないかを選べます
  - どれにも当たらない行がセリフで、文字数はセリフだけを数えます
- 「縦書き／横書き」「ト書きあり／なし」で切り替え、「印刷して PDF に」→ 印刷の画面で「PDF に保存」
- ルビ：`|漢字《かんじ》`・`漢字《かんじ》`（| が無いときは《 の前に続く漢字）・`[[rb:漢字 > かんじ]]`（pixiv）を読みます。記号は「ルビの書き方」で変えられます。ルビの字は文字数に入れません
- 「この設定で保存」で、記号などの設定を `daihon.json` としてこの PC に落とします。次からは「設定を開く」で選びます（ログインは要りません。CLI もそのまま読めます）
- 貼るとき、日本語入力のままの記号（行の頭の `／／` `＃` `（` `￥`、`｛｝` など）は daihon で打ったときと同じに半角にします
- 設定は「設定」の欄に daihon.json の形で書きます。塊（`{名前}`）は「塊を読む」で parts/ の .txt を選びます
- 貼った台本は、どこにも送らず保存もしません（閉じると消えます）

### 台本を受け取らない・覚えない

- ページは外と通信しません。`web/index.html` の CSP（`default-src 'none'`）で、ブラウザが外への通信を全部止めます。開発者ツールの「ネットワーク」で確かめられます
- ブラウザの保存（localStorage・cookie など）も使いません
- 作った人が台本を見ることも、AI の学習に使うこともできません（届かないので）

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
