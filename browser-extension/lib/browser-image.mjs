const MAX_EDGE = 32_767;
const MAX_OUTPUT_PIXELS = 32_000_000;
const DIMENSION_TOLERANCE = 1.1;

function fail(message) {
  throw new Error(message);
}

function validMetrics(metrics) {
  const values = [metrics?.viewportWidth, metrics?.viewportHeight, metrics?.scrollY,
    metrics?.documentHeight, metrics?.devicePixelRatio];
  if (!values.every(Number.isFinite) || metrics.viewportWidth <= 0 || metrics.viewportHeight <= 0 ||
      metrics.scrollY < 0 || metrics.scrollY > metrics.documentHeight ||
      metrics.documentHeight <= 0 || metrics.devicePixelRatio <= 0) {
    fail("invalid_metrics");
  }
}

function assertCanvasSize(width, height) {
  // The pixel budget caps each canvas allocation; growth briefly needs old and new canvases.
  if (!Number.isInteger(width) || !Number.isInteger(height) || width <= 0 || height <= 0 ||
      width > MAX_EDGE || height > MAX_EDGE || width * height > MAX_OUTPUT_PIXELS) {
    fail("browser_image_too_large");
  }
}

function context2d(canvas) {
  const context = canvas.getContext("2d");
  if (!context) fail("browser_image_failed");
  return context;
}

function releaseCanvas(canvas) {
  if (!canvas) return;
  canvas.width = 0;
  canvas.height = 0;
}

export class BrowserCaptureImage {
  #runtime;
  #canvas = null;
  #scale = null;
  #viewportWidth = null;
  #viewportHeight = null;
  #coverage = 0;
  #documentHeight = 0;
  #disposed = false;
  #finished = false;
  #tail = Promise.resolve();
  #temporaryCanvases = new Set();

  constructor(runtime = globalThis) {
    this.#runtime = runtime;
  }

  addTile(metrics, pngBase64) {
    const task = this.#tail.then(() => this.#addTile(metrics, pngBase64));
    this.#tail = task.catch(() => {});
    return task;
  }

  async #addTile(metrics, pngBase64) {
    this.#assertActive();
    validMetrics(metrics);
    if (typeof pngBase64 !== "string" || !pngBase64) fail("invalid_png");

    let bitmap;
    try {
      const binary = this.#runtime.atob(pngBase64);
      const bytes = Uint8Array.from(binary, (char) => char.charCodeAt(0));
      bitmap = await this.#runtime.createImageBitmap(new this.#runtime.Blob([bytes], { type: "image/png" }));
      this.#assertActive();
      const width = bitmap.width;
      const height = bitmap.height;
      if (!Number.isInteger(width) || !Number.isInteger(height) || width <= 0 || height <= 0) fail("invalid_png");
      if (width > MAX_EDGE || height > MAX_EDGE) fail("browser_image_too_large");

      const scale = width / metrics.viewportWidth;
      if (!Number.isFinite(scale) || scale <= 0 || Math.abs(height - metrics.viewportHeight * scale) > DIMENSION_TOLERANCE) {
        fail("invalid_png_geometry");
      }
      if (this.#scale !== null && (Math.abs(scale - this.#scale) > 0.001 ||
          metrics.viewportWidth !== this.#viewportWidth || metrics.viewportHeight !== this.#viewportHeight)) {
        fail("inconsistent_tile_geometry");
      }

      const tileY = Math.round(metrics.scrollY * scale);
      if (this.#scale === null && tileY !== 0) fail("first_tile_must_start_at_top");
      if (tileY > this.#coverage) fail("capture_gap");

      const targetCoverage = Math.max(this.#coverage, tileY + height);
      assertCanvasSize(width, targetCoverage);
      if (!this.#canvas) {
        this.#canvas = new this.#runtime.OffscreenCanvas(width, targetCoverage);
      } else if (targetCoverage > this.#canvas.height) {
        const previous = this.#canvas;
        const expanded = new this.#runtime.OffscreenCanvas(width, targetCoverage);
        this.#temporaryCanvases.add(expanded);
        try {
          context2d(expanded).drawImage(previous, 0, 0);
          this.#assertActive();
          releaseCanvas(previous);
          this.#canvas = expanded;
          this.#temporaryCanvases.delete(expanded);
        } catch (error) {
          releaseCanvas(expanded);
          this.#temporaryCanvases.delete(expanded);
          throw error;
        }
      }

      if (height + tileY > this.#coverage) {
        // Skip the overlap so fixed headers and earlier page pixels remain from the first tile.
        const sourceY = this.#coverage - tileY;
        const sourceHeight = height - sourceY;
        const context = context2d(this.#canvas);
        this.#assertActive();
        context.drawImage(bitmap, 0, sourceY, width, sourceHeight,
          0, this.#coverage, width, sourceHeight);
      }

      this.#scale ??= scale;
      this.#viewportWidth ??= metrics.viewportWidth;
      this.#viewportHeight ??= metrics.viewportHeight;
      this.#coverage = targetCoverage;
      this.#documentHeight = Math.max(this.#documentHeight, metrics.documentHeight);
    } finally {
      bitmap?.close();
    }
  }

  async finish(capturedHeight) {
    await this.#tail;
    this.#assertActive();
    if (!this.#canvas || this.#coverage <= 0) fail("browser_image_empty");
    if (!Number.isFinite(capturedHeight) || capturedHeight <= 0) fail("invalid_metrics");
    const requestedHeight = Math.round(Math.min(capturedHeight, this.#documentHeight) * this.#scale);
    if (requestedHeight > this.#coverage + 1) fail("incomplete_coverage");
    const outputHeight = Math.min(this.#coverage, requestedHeight);
    if (outputHeight <= 0) fail("browser_image_empty");
    assertCanvasSize(this.#canvas.width, outputHeight);

    let output = this.#canvas;
    const temporary = outputHeight !== this.#canvas.height;
    if (temporary) {
      output = new this.#runtime.OffscreenCanvas(this.#canvas.width, outputHeight);
      this.#temporaryCanvases.add(output);
    }
    try {
      if (temporary) {
        context2d(output).drawImage(this.#canvas, 0, 0, this.#canvas.width, outputHeight,
          0, 0, this.#canvas.width, outputHeight);
      }
      let blob;
      try {
        blob = await output.convertToBlob({ type: "image/png" });
      } catch {
        fail("browser_image_failed");
      }
      this.#assertActive();
      this.#finished = true;
      return blob;
    } finally {
      if (temporary) {
        releaseCanvas(output);
        this.#temporaryCanvases.delete(output);
      }
    }
  }

  dispose() {
    if (this.#disposed) return;
    this.#disposed = true;
    for (const canvas of this.#temporaryCanvases) releaseCanvas(canvas);
    this.#temporaryCanvases.clear();
    releaseCanvas(this.#canvas);
    this.#canvas = null;
  }

  #assertActive() {
    if (this.#disposed) fail("browser_image_disposed");
    if (this.#finished) fail("browser_image_failed");
  }
}
