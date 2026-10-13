import test, { after } from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { readFile } from "node:fs/promises";
import { nextTarget, tileCropRect } from "../lib/planner.mjs";

// Run explicitly with Playwright available; ordinary unit tests stay browser-free.
const { chromium } = createRequire(import.meta.url)("playwright");
const browser = await chromium.launch({ channel: "chrome", headless: true });
after(() => browser.close());
const source = await readFile(new URL("../capture.js", import.meta.url), "utf8");

async function pageFor(html, scale = 1) {
  const context = await browser.newContext({ viewport: { width: 900, height: 600 }, deviceScaleFactor: scale });
  const page = await context.newPage();
  await page.setContent(`<!doctype html>${html}`);
  await page.evaluate(() => { window.chrome = { runtime: {
    id: "fixture", onMessage: { addListener() {} }, sendMessage: async () => ({})
  } }; });
  await page.addScriptTag({ content: source });
  return { page, context };
}

test("real Chrome captures an inner pane, crops Retina pixels and restores both scroll positions", async () => {
  const { page, context } = await pageFor(`<style>
    html,body{margin:0;overflow:hidden} #pane{position:fixed;left:100px;top:80px;width:600px;height:440px;overflow:auto}
    .row{height:100px;background:rgb(20,120,220)} .heading{position:sticky;top:10px;height:60px;background:rgb(240,20,180)}
    </style><div id="pane"><div style="height:900px"></div><div class="heading">Below-first-screen heading</div><div style="height:1200px"></div></div>`, 2);
  try {
    await page.evaluate(() => { document.querySelector("#pane").scrollTop = 180; });
    const initial = await page.evaluate(() => window.__pinboardShotCapture.prepare());
    assert.equal(initial.originalScrollY, 180);
    assert.equal(initial.viewportWidth, 600);
    assert.deepEqual(initial.captureRect, { x: 100, y: 80, width: 600, height: 440 });
    const metrics = await page.evaluate(() => window.__pinboardShotCapture.goTo(800, true));
    assert.equal(metrics.scrollY, 800);
    assert.equal(await page.locator(".heading").evaluate(e => getComputedStyle(e).visibility), "visible");
    assert.equal(await page.locator(".heading").evaluate(e => e.getBoundingClientRect().top), 180);
    const png = (await page.screenshot()).toString("base64");
    const crop = tileCropRect(metrics, 1800, 1200);
    const sampled = await page.evaluate(async ({ png, crop }) => {
      const bitmap = await createImageBitmap(new Blob([Uint8Array.from(atob(png), c => c.charCodeAt(0))], { type: "image/png" }));
      const canvas = new OffscreenCanvas(crop.width, crop.height);
      const ctx = canvas.getContext("2d");
      ctx.drawImage(bitmap, crop.x, crop.y, crop.width, crop.height, 0, 0, crop.width, crop.height);
      bitmap.close();
      return { width: canvas.width, height: canvas.height, heading: Array.from(ctx.getImageData(20, 220, 1, 1).data) };
    }, { png, crop });
    assert.deepEqual(sampled, { width: 1200, height: 880, heading: [240, 20, 180, 255] });
    await page.evaluate(() => window.__pinboardShotCapture.restore());
    assert.equal(await page.locator("#pane").evaluate(e => e.scrollTop), 180);
    assert.equal(await page.locator(".heading").evaluate(e => getComputedStyle(e).position), "sticky");
    assert.equal(await page.evaluate(() => window.scrollY), 0);
  } finally { await context.close(); }
});

test("real rendered tiles recover content beneath a footer taller than the default overlap", async () => {
  const rows = Array.from({ length: 22 }, (_, i) => `<div style="height:100px;background:rgb(${i * 10},80,120)"></div>`).join("");
  const { page, context } = await pageFor(`<style>html,body{margin:0}</style>${rows}<div style="position:fixed;bottom:0;width:100%;height:210px;background:red"></div>`);
  try {
    const initial = await page.evaluate(() => window.__pinboardShotCapture.prepare());
    assert.ok(initial.requiredOverlap > 0.35);
    const tiles = [];
    let y = 0;
    do {
      const metrics = await page.evaluate(({ y, later }) => window.__pinboardShotCapture.goTo(y, later), { y, later: tiles.length > 0 });
      tiles.push({ y: metrics.scrollY, png: (await page.screenshot()).toString("base64") });
      y = nextTarget(metrics.scrollY, metrics.documentHeight, metrics.viewportHeight, metrics.requiredOverlap);
    } while (y !== null);
    const rows = await page.evaluate(async tiles => {
      const canvas = new OffscreenCanvas(900, 2200);
      const ctx = canvas.getContext("2d");
      for (const tile of tiles) {
        const bitmap = await createImageBitmap(new Blob([Uint8Array.from(atob(tile.png), c => c.charCodeAt(0))], { type: "image/png" }));
        ctx.drawImage(bitmap, 0, tile.y);
        bitmap.close();
      }
      return Array.from({ length: 2200 }, (_, y) => Array.from(ctx.getImageData(30, y, 1, 1).data));
    }, tiles);
    assert.ok(rows.every((pixel, y) => pixel[0] === Math.floor(y / 100) * 10 && pixel[1] === 80 && pixel[2] === 120 && pixel[3] === 255));
    await page.evaluate(() => window.__pinboardShotCapture.restore());
    assert.equal(await page.locator("body > div").last().evaluate(e => e.style.visibility), "");
  } finally { await context.close(); }
});

test("two substantial panes are rejected instead of reporting the outer shell as complete", async () => {
  const { page, context } = await pageFor(`<style>html,body{margin:0;overflow:hidden}.pane{position:absolute;top:30px;width:440px;height:550px;overflow:auto}.pane div{height:2000px}</style><div class="pane" style="left:0"><div>A</div></div><div class="pane" style="left:450px"><div>B</div></div>`);
  try {
    const result = await page.evaluate(() => {
      try { window.__pinboardShotCapture.prepare(); return "unexpected_success"; }
      catch (error) { return error.message; }
    });
    assert.equal(result, "multiple_scroll_regions");
    assert.equal(await page.evaluate(() => Boolean(window.__pinboardShotCaptureState)), false);
  } finally { await context.close(); }
});

test("a clipped inner pane cannot silently crop away its hidden edge", async () => {
  const { page, context } = await pageFor(`<style>html,body{margin:0;overflow:hidden}#pane{position:absolute;left:200px;top:80px;width:800px;height:500px;overflow:auto}#pane div{height:2000px}</style><div id="pane"><div>Content</div></div>`);
  try {
    assert.equal(await page.evaluate(() => {
      try { window.__pinboardShotCapture.prepare(); return "unexpected_success"; }
      catch (error) { return error.message; }
    }), "scroll_container_not_visible");
  } finally { await context.close(); }
});

test("a pane clipped by an ancestor is rejected even when its own rectangle fits the viewport", async () => {
  const { page, context } = await pageFor(`<style>html,body{margin:0;overflow:hidden}#clip{position:absolute;left:40px;top:30px;width:500px;height:250px;overflow:hidden}#pane{width:600px;height:500px;overflow:auto}#pane div{height:2000px}</style><div id="clip"><div id="pane"><div>Content</div></div></div>`);
  try {
    assert.equal(await page.evaluate(() => {
      try { window.__pinboardShotCapture.prepare(); return "unexpected_success"; }
      catch (error) { return error.message; }
    }), "scroll_container_not_visible");
  } finally { await context.close(); }
});

test("a substantial nested scroller cannot be hidden by selecting its larger outer pane", async () => {
  const { page, context } = await pageFor(`<style>html,body{margin:0;overflow:hidden}#outer{position:absolute;left:10px;top:10px;width:880px;height:560px;overflow:auto}#inner{width:500px;height:400px;overflow:auto}#inner div{height:2000px}</style><div id="outer"><div style="height:80px"></div><div id="inner"><div>Nested content</div></div><div style="height:300px"></div></div>`);
  try {
    assert.equal(await page.evaluate(() => {
      try { window.__pinboardShotCapture.prepare(); return "unexpected_success"; }
      catch (error) { return error.message; }
    }), "multiple_scroll_regions");
  } finally { await context.close(); }
});
