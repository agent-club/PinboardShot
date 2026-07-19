import assert from "node:assert/strict";
import test from "node:test";
import currentRelease from "../content/current-release.json" with { type: "json" };

async function render() {
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set("test", `${process.pid}-${Date.now()}`);
  const { default: worker } = await import(workerUrl.href);

  return worker.fetch(
    new Request("https://pinboardshot.example/", {
      headers: { accept: "text/html" },
    }),
    {
      ASSETS: {
        fetch: async () => new Response("Not found", { status: 404 }),
      },
    },
    {
      waitUntil() {},
      passThroughOnException() {},
    },
  );
}

test("server-renders the PinboardShot download page", async () => {
  const response = await render();
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);

  const html = await response.text();
  assert.match(html, /<title>PinboardShot — Capture it\. Keep it in sight\.<\/title>/i);
  assert.match(html, /href="\/PinboardShot\.zip"/i);
  assert.match(html, /href="\/PinboardShot\.zip\.sha256"/i);
  assert.ok(html.includes(currentRelease.version));
  assert.match(html, /Your screenshots stay|你的截图/);
});
