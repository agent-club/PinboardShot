import test from "node:test";
import assert from "node:assert/strict";
import { BrowserCaptureImage } from "../lib/browser-image.mjs";

function createRuntime() {
  const canvases = [];
  const bitmaps = [];
  class TestCanvas {
    constructor(width, height) {
      this.width = width;
      this.height = height;
      this.draws = [];
      this.blobOptions = null;
      canvases.push(this);
    }
    getContext() {
      return { drawImage: (...args) => this.draws.push(args) };
    }
    async convertToBlob(options) {
      this.blobOptions = options;
      return { type: options.type, width: this.width, height: this.height };
    }
  }
  return {
    canvases,
    bitmaps,
    runtime: {
      Blob,
      OffscreenCanvas: TestCanvas,
      atob,
      async createImageBitmap() {
        const bitmap = { width: 200, height: 120, closed: false, close() { this.closed = true; } };
        bitmaps.push(bitmap);
        return bitmap;
      },
    },
  };
}

const png = "dGVzdA==";
const metrics = (overrides = {}) => ({
  viewportWidth: 100,
  viewportHeight: 60,
  scrollY: 0,
  documentHeight: 200,
  devicePixelRatio: 1,
  ...overrides,
});

test("derives image scale from decoded PNG width and draws only the uncovered overlap tail", async () => {
  const { runtime, canvases, bitmaps } = createRuntime();
  const image = new BrowserCaptureImage(runtime);
  await image.addTile(metrics(), png);
  await image.addTile(metrics({ scrollY: 40 }), png);

  const canvas = canvases.at(-1);
  const tail = canvas.draws.at(-1);
  assert.equal(canvas.width, 200);
  assert.equal(canvas.height, 200);
  assert.deepEqual(tail.slice(1), [0, 40, 200, 80, 0, 120, 200, 80]);
  assert.equal(bitmaps.every((bitmap) => bitmap.closed), true);
  image.dispose();
});

test("finish crops a partial stop to captured CSS height and returns PNG", async () => {
  const { runtime, canvases } = createRuntime();
  const image = new BrowserCaptureImage(runtime);
  await image.addTile(metrics(), png);
  await image.addTile(metrics({ scrollY: 40 }), png);

  const result = await image.finish(70);
  assert.deepEqual(result, { type: "image/png", width: 200, height: 140 });
  assert.deepEqual(canvases.at(-1).draws.at(-1).slice(1), [0, 0, 200, 140, 0, 0, 200, 140]);
  assert.equal(canvases.at(-1).width, 0);
  assert.equal(canvases.at(-1).height, 0);
  image.dispose();
});

test("finish rejects coverage overclaims and permits one pixel of rounding excess", async () => {
  const { runtime, canvases } = createRuntime();
  const image = new BrowserCaptureImage(runtime);
  await image.addTile(metrics(), png);

  await assert.rejects(image.finish(70), /incomplete_coverage/);
  assert.equal(canvases[0].blobOptions, null);
  const result = await image.finish(60.4);
  assert.equal(result.height, 120);
  image.dispose();
});

test("short pages finish at documentHeight without a white extension", async () => {
  const { runtime, canvases } = createRuntime();
  const image = new BrowserCaptureImage(runtime);
  await image.addTile(metrics({ documentHeight: 30 }), png);

  const result = await image.finish(60);
  assert.equal(result.height, 60);
  assert.deepEqual(canvases.at(-1).draws.at(-1).slice(1), [0, 0, 200, 60, 0, 0, 200, 60]);
  image.dispose();
});

test("growing document height expands the canvas and preserves its prior pixels", async () => {
  const { runtime, canvases } = createRuntime();
  const image = new BrowserCaptureImage(runtime);
  await image.addTile(metrics({ documentHeight: 100 }), png);
  const first = canvases[0];
  await image.addTile(metrics({ scrollY: 40, documentHeight: 120 }), png);

  const expanded = canvases.at(-1);
  assert.notEqual(expanded, first);
  assert.deepEqual(expanded.draws[0], [first, 0, 0]);
  assert.equal(first.width, 0);
  assert.equal(first.height, 0);
  assert.equal(expanded.height, 200);
  image.dispose();
});

test("failed expansion releases its temporary canvas and keeps the prior canvas usable", async () => {
  const { runtime, canvases } = createRuntime();
  const baseGetContext = runtime.OffscreenCanvas.prototype.getContext;
  runtime.OffscreenCanvas.prototype.getContext = function (...args) {
    return this === canvases[1] ? null : baseGetContext.apply(this, args);
  };
  const image = new BrowserCaptureImage(runtime);
  await image.addTile(metrics(), png);
  await assert.rejects(image.addTile(metrics({ scrollY: 40 }), png), /browser_image_failed/);
  assert.deepEqual([canvases[1].width, canvases[1].height], [0, 0]);
  assert.deepEqual([canvases[0].width, canvases[0].height], [200, 120]);
  assert.equal((await image.finish(60)).height, 120);
  image.dispose();
});

test("null 2D contexts fail explicitly and release a finish crop canvas", async () => {
  const initial = createRuntime();
  initial.runtime.OffscreenCanvas.prototype.getContext = () => null;
  const firstImage = new BrowserCaptureImage(initial.runtime);
  await assert.rejects(firstImage.addTile(metrics(), png), /browser_image_failed/);
  firstImage.dispose();

  const cropped = createRuntime();
  const baseGetContext = cropped.runtime.OffscreenCanvas.prototype.getContext;
  cropped.runtime.OffscreenCanvas.prototype.getContext = function (...args) {
    return this === cropped.canvases[1] ? null : baseGetContext.apply(this, args);
  };
  const croppedImage = new BrowserCaptureImage(cropped.runtime);
  await croppedImage.addTile(metrics(), png);
  await assert.rejects(croppedImage.finish(30), /browser_image_failed/);
  assert.deepEqual([cropped.canvases[1].width, cropped.canvases[1].height], [0, 0]);
  croppedImage.dispose();
});

test("rejects a first tile below the top and rejects gaps, closing decoded images", async () => {
  const first = createRuntime();
  const image = new BrowserCaptureImage(first.runtime);
  await assert.rejects(image.addTile(metrics({ scrollY: 1 }), png), /first_tile_must_start_at_top/);
  assert.equal(first.bitmaps[0].closed, true);
  await image.addTile(metrics(), png);
  await assert.rejects(image.addTile(metrics({ scrollY: 61 }), png), /capture_gap/);
  assert.equal(first.bitmaps.at(-1).closed, true);
  assert.equal((await image.finish(60)).height, 120);
  image.dispose();
});

test("rejects inconsistent image geometry and size budgets without producing output", async () => {
  const { runtime, bitmaps } = createRuntime();
  const image = new BrowserCaptureImage(runtime);
  await image.addTile(metrics(), png);
  await assert.rejects(image.addTile(metrics({ scrollY: 40, viewportWidth: 90 }), png), /invalid_png_geometry|inconsistent_tile_geometry/);
  assert.equal(bitmaps.at(-1).closed, true);
  image.dispose();

  const oversized = createRuntime();
  oversized.runtime.createImageBitmap = async () => ({ width: 8000, height: 5000, close() { this.closed = true; } });
  const largeImage = new BrowserCaptureImage(oversized.runtime);
  await assert.rejects(largeImage.addTile(metrics({ viewportWidth: 8000, viewportHeight: 5000 }), png), /browser_image_too_large/);
  assert.equal(oversized.canvases.length, 0);
  largeImage.dispose();
});

test("dispose prevents an in-flight decode from drawing or retaining a canvas", async () => {
  const { runtime, canvases, bitmaps } = createRuntime();
  let resolveBitmap;
  const lateBitmap = { width: 200, height: 120, closed: false, close() { this.closed = true; } };
  runtime.createImageBitmap = () => new Promise((resolve) => { resolveBitmap = resolve; });
  const image = new BrowserCaptureImage(runtime);
  const adding = image.addTile(metrics(), png);
  await new Promise((resolve) => setImmediate(resolve));
  image.dispose();
  resolveBitmap(lateBitmap);
  await assert.rejects(adding, /browser_image_disposed/);
  assert.equal(canvases.length, 0);
  assert.equal(lateBitmap.closed, true);
  assert.equal(await image.finish(60).catch((error) => error.message), "browser_image_disposed");
  assert.equal(bitmaps.length, 0);
});

test("dispose during blob conversion releases the temporary output canvas", async () => {
  const { runtime, canvases } = createRuntime();
  let resolveBlob;
  runtime.OffscreenCanvas.prototype.convertToBlob = function () {
    return new Promise((resolve) => { resolveBlob = () => resolve({ width: this.width, height: this.height }); });
  };
  const image = new BrowserCaptureImage(runtime);
  await image.addTile(metrics(), png);
  const finishing = image.finish(30);
  await new Promise((resolve) => setImmediate(resolve));
  const temporary = canvases.at(-1);
  assert.equal(canvases.length, 2);
  image.dispose();
  assert.deepEqual([temporary.width, temporary.height], [0, 0]);
  resolveBlob();
  await assert.rejects(finishing, /browser_image_disposed/);
  assert.deepEqual([temporary.width, temporary.height], [0, 0]);
});

test("empty finish and blob conversion failure return explicit errors", async () => {
  const empty = createRuntime();
  const emptyImage = new BrowserCaptureImage(empty.runtime);
  await assert.rejects(emptyImage.finish(10), /browser_image_empty/);
  emptyImage.dispose();

  const failing = createRuntime();
  failing.runtime.OffscreenCanvas.prototype.convertToBlob = async () => { throw new Error("conversion detail"); };
  const image = new BrowserCaptureImage(failing.runtime);
  await image.addTile(metrics(), png);
  await assert.rejects(image.finish(60), /browser_image_failed/);
  image.dispose();
});
