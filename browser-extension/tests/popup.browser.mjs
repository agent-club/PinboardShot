import test, { after } from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { readFile } from "node:fs/promises";

// Explicit UI verification uses synthetic states and an isolated Chrome profile.
const { chromium } = createRequire(import.meta.url)("playwright");
const browser = await chromium.launch({ channel: "chrome", headless: true });
after(() => browser.close());

async function panel({ width = 320, language = "zh", colorScheme = "light", state = { status: "idle" } } = {}) {
  const context = await browser.newContext({ viewport: { width, height: 800 }, colorScheme });
  const page = await context.newPage();
  const assets = ["popup.html", "popup.js", "popup.css", "icons/icon128.png", "icons/capture-scene.png", ...["pause", "play", "stop", "check", "x", "warning-circle", "scan", "arrow-right"].map(name => `icons/ui-${name}.svg`)];
  const files = new Map(await Promise.all(assets.map(async name => [name, await readFile(new URL(`../${name}`, import.meta.url))])));
  await page.route("https://panel.pinboardshot.test/**", async route => {
    const name = new URL(route.request().url()).pathname.slice(1);
    const body = files.get(name);
    if (!body) return route.abort();
    await route.fulfill({ body, contentType: name.endsWith("html") ? "text/html" : name.endsWith("js") ? "text/javascript" : name.endsWith("css") ? "text/css" : name.endsWith("svg") ? "image/svg+xml" : "image/png" });
  });
  await page.addInitScript(({ language, state }) => {
    localStorage.setItem("pinboardshot.language", language);
    window.panelState = state;
    window.chrome = { runtime: {
      onMessage: { addListener(listener) { window.panelListener = listener; } },
      sendMessage: async message => message.type === "connectionRequest" ? { ok: true, connection: { status: "connected" } } : { ok: true, state: window.panelState }
    } };
  }, { language, state });
  await page.goto("https://panel.pinboardshot.test/popup.html");
  await page.waitForFunction(() => document.querySelector("#connection").textContent.includes("Connected") || document.querySelector("#connection").textContent.includes("已连接"));
  return { page, context };
}

test("rendered panel clears completed progress in both languages and color schemes", async () => {
  for (const language of ["zh", "en"]) for (const colorScheme of ["light", "dark"]) {
    const { page, context } = await panel({ language, colorScheme });
    try {
      for (const status of ["capturing", "paused", "stopping", "cancelling", "cancelled", "stopped", "stopped_empty", "complete", "error"]) {
        await page.evaluate(status => {
          window.panelState = { status, progress: status === "complete" ? 100 : 42, error: "viewport_changed" };
          window.panelListener({ channel: "pinboardshot.capture", type: "state", state: window.panelState });
        }, status);
        const active = ["capturing", "paused", "stopping", "cancelling"].includes(status);
        assert.equal(await page.locator("#progressArea").isVisible(), active, `${language}/${colorScheme}/${status}`);
        assert.equal(await page.locator("#start").isVisible(), !active);
        if (!active) {
          assert.equal(await page.locator("#progressPercent").textContent(), "");
          assert.ok(await page.locator("#message").textContent());
        }
        assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth), false, `${language}/${status} overflow`);
      }
    } finally { await context.close(); }
  }
});

test("a narrow English panel keeps active controls reachable", async () => {
  const { page, context } = await panel({ width: 280, language: "en", state: { status: "capturing", progress: 42 } });
  try {
    for (const id of ["pause", "stop", "cancel"]) {
      const control = page.locator(`#${id}`);
      assert.equal(await control.isVisible(), true);
      const bounds = await control.boundingBox();
      assert.ok(bounds.x >= 0 && bounds.x + bounds.width <= 280);
      assert.ok(bounds.height >= 32);
    }
  } finally { await context.close(); }
});
