// CLI：HTML を2つ書く（PDF は作らない）。元の daihon と同じ HTML になるか
import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, writeFileSync, mkdirSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

const BIN = new URL("../bin/daihon-pdf.js", import.meta.url).pathname;
const SAMPLE = new URL("./fixtures/sample/", import.meta.url).pathname;
const run = (args) => spawnSync(process.execPath, [BIN, ...args], { encoding: "utf8" });

test("CLI：例の台本から HTML を2つ書く", () => {
  const out = mkdtempSync(join(tmpdir(), "daihon-pdf-"));
  const res = run([join(SAMPLE, "台本.txt"), "--config", join(SAMPLE, "daihon.json"), "--out", out, "--no-pdf"]);
  assert.equal(res.status, 0, res.stderr);
  for (const name of ["台本_ト書きあり", "台本_ト書きなし"]) {
    assert.equal(
      readFileSync(join(out, `${name}.html`), "utf8"),
      readFileSync(join(SAMPLE, "expected", `${name}.html`), "utf8"),
    );
  }
});

test("CLI：設定が無ければ既定値。out/ は台本のフォルダに。未登録の塊と、使わない設定を知らせる", () => {
  const dir = mkdtempSync(join(tmpdir(), "daihon-pdf-"));
  writeFileSync(join(dir, "a.txt"), "ただいま\n{ない}\n{../a}\n");
  let res = run([join(dir, "a.txt"), "--no-pdf"]);
  assert.equal(res.status, 0, res.stderr);
  assert.ok(existsSync(join(dir, "out", "a_ト書きあり.html")));
  assert.match(res.stderr, /未登録の塊はそのまま出しました：\.\.\/a、ない/);

  writeFileSync(join(dir, "daihon.json"), JSON.stringify({ export: { dir: "pdf", pdf: { both: false, command: ["rm"] } } }));
  res = run([join(dir, "a.txt"), "--no-pdf"]);
  assert.equal(res.status, 0, res.stderr);
  assert.ok(existsSync(join(dir, "pdf", "a_ト書きあり.html")));
  assert.ok(!existsSync(join(dir, "pdf", "a_ト書きなし.html")));
  assert.match(res.stderr, /export\.pdf\.command は使いません/);
});

test("CLI：まちがった設定・無い台本は止まって知らせる", () => {
  const dir = mkdtempSync(join(tmpdir(), "daihon-pdf-"));
  mkdirSync(join(dir, "w"));
  writeFileSync(join(dir, "w", "a.txt"), "あ\n");
  writeFileSync(join(dir, "w", "daihon.json"), JSON.stringify({ mode: "two" }));
  let res = run([join(dir, "w", "a.txt"), "--no-pdf"]);
  assert.equal(res.status, 1);
  assert.match(res.stderr, /mode は "solo" か "multi" です/);
  res = run([join(dir, "nai.txt")]);
  assert.equal(res.status, 1);
  assert.match(res.stderr, /台本が見つかりません/);
});
