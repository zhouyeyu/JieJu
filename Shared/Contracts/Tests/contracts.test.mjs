import test from "node:test";
import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";
import { fileURLToPath } from "node:url";

const directory = fileURLToPath(new URL("../v1/", import.meta.url));

async function json(name) {
  return JSON.parse(await readFile(new URL(`../v1/${name}`, import.meta.url), "utf8"));
}

test("manifest lists every v1 schema and every schema is Draft 2020-12", async () => {
  const manifest = await json("manifest.json");
  assert.equal(manifest.contractVersion, 1);
  const files = (await readdir(directory)).filter(name => name.endsWith(".schema.json")).sort();
  assert.deepEqual([...manifest.schemas].sort(), files);
  for (const name of files) {
    const schema = await json(name);
    assert.equal(schema.$schema, "https://json-schema.org/draft/2020-12/schema");
    assert.match(schema.$id, /\/contracts\/v1\//);
  }
});

test("security-sensitive settings are absent from persisted contracts", async () => {
  const schemas = await Promise.all((await json("manifest.json")).schemas.map(json));
  const text = JSON.stringify(schemas).toLowerCase();
  assert.equal(text.includes("apikey"), false);
  assert.equal(text.includes("authorization"), false);
  assert.equal(text.includes("accesstoken"), false);
});

test("reader bridge reserves stable locators instead of global page numbers", async () => {
  const schema = await json("reader-bridge.schema.json");
  const locator = schema.$defs.locator;
  assert.equal(locator.oneOf[0].properties.kind.const, "pdf");
  assert.equal(locator.oneOf[1].properties.kind.const, "epub");
  assert.ok(locator.oneOf[1].properties.cfi);
  assert.equal(JSON.stringify(locator).includes("globalPageIndex"), false);
});

test("every local schema reference resolves", async () => {
  const manifest = await json("manifest.json");
  for (const name of manifest.schemas) {
    const source = await json(name);
    for (const reference of referencesIn(source)) {
      const [fileName, fragment = ""] = reference.split("#");
      const target = fileName ? await json(fileName) : source;
      let value = target;
      if (fragment) {
        assert.ok(fragment.startsWith("/"), `Unsupported reference fragment: ${reference}`);
        for (const part of fragment.slice(1).split("/")) {
          const key = part.replaceAll("~1", "/").replaceAll("~0", "~");
          assert.ok(value && Object.hasOwn(value, key), `Missing reference: ${name} -> ${reference}`);
          value = value[key];
        }
      }
      assert.ok(value, `Missing reference: ${name} -> ${reference}`);
    }
  }
});

test("v2 adds vocabulary without changing the v1 library", async () => {
  const manifest = JSON.parse(await readFile(new URL("../v2/manifest.json", import.meta.url), "utf8"));
  const schema = JSON.parse(await readFile(new URL("../v2/learning-library.schema.json", import.meta.url), "utf8"));
  assert.equal(manifest.contractVersion, 2);
  assert.deepEqual(manifest.schemas, ["learning-library.schema.json"]);
  assert.equal(schema.properties.schemaVersion.const, 2);
  assert.ok(schema.properties.vocabularyEntries);
  assert.ok(schema.$defs.vocabularyEntry.properties.sources);
  assert.equal(JSON.stringify(schema).toLowerCase().includes("apikey"), false);
});

function referencesIn(value, result = []) {
  if (Array.isArray(value)) value.forEach(item => referencesIn(item, result));
  else if (value && typeof value === "object") {
    if (typeof value.$ref === "string") result.push(value.$ref);
    Object.values(value).forEach(item => referencesIn(item, result));
  }
  return result;
}
