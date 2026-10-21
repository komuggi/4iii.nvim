// 元の daihon（Lua）が作った HTML と、1文字も違わないか
// 正解は test/make_expected.lua で作った（daihon のコミットは fixtures/DAIHON_COMMIT）
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync, existsSync } from "node:fs";
import { join } from "node:path";
import { makeConfig, render, splitLines } from "../src/index.js";

const FIXTURES = new URL("./fixtures/", import.meta.url).pathname;
const CASES = ["sample", "multi_kagi", "colon_horizontal", "custom_ranges", "crlf_bom", "empty"];

function load(dir) {
  const cfg = makeConfig(JSON.parse(readFileSync(join(dir, "daihon.json"), "utf8")));
  const txt = readdirSync(dir).find((f) => f.endsWith(".txt"));
  const getPart = (name) => {
    const path = join(dir, cfg.parts_dir, `${name}.txt`);
    return existsSync(path) ? splitLines(readFileSync(path, "utf8")) : undefined;
  };
  const css = cfg.export.pdf.css ? splitLines(readFileSync(join(dir, cfg.export.pdf.css), "utf8")).join("\n") : undefined;
  return { cfg, text: readFileSync(join(dir, txt), "utf8"), name: txt.slice(0, -4), getPart, css };
}

for (const name of CASES) {
  test(`元の daihon と同じ HTML：${name}`, () => {
    const dir = join(FIXTURES, name);
    const { cfg, text, name: base, getPart, css } = load(dir);
    const res = render(text, cfg, { name: base, getPart, css });
    const expected = readdirSync(join(dir, "expected")).filter((f) => f.endsWith(".html")).sort();
    assert.deepEqual(res.outputs.map((o) => `${o.name}.html`).sort(), expected);
    for (const o of res.outputs) {
      assert.equal(o.html, readFileSync(join(dir, "expected", `${o.name}.html`), "utf8"), o.name);
    }
    assert.deepEqual(res.missing, JSON.parse(readFileSync(join(dir, "expected", "missing.json"), "utf8")));
  });
}

// examples/sample/out/ の HTML は、今の 台本.txt より前の台本から作った物（out/ は git に入っていない）
// 本文は比べられないので、head（CSS）と、本文の外側の形だけを比べる
test("examples/sample/out の HTML と head（CSS）が同じ", () => {
  const { cfg, text, getPart } = load(join(FIXTURES, "sample"));
  const res = render(text, cfg, { name: "台本", getPart });
  for (const o of res.outputs) {
    const old = readFileSync(join(FIXTURES, "old_out", `${o.name}.html`), "utf8");
    const head = (s) => s.slice(0, s.indexOf("<body>"));
    assert.equal(head(o.html), head(old), o.name);
    // 終わり：今の daihon は "</html>\n"、古い out/ は "</html>\n\n"
    assert.ok(old.endsWith("</html>\n\n"));
    assert.ok(o.html.endsWith("</html>\n") && !o.html.endsWith("\n\n"));
  }
});
