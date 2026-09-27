export const DEFAULT_OVERLAP = 0.15;
export const MIN_CAPTURE_INTERVAL_MS = 650;
export const MAX_CAPTURE_MS = 5 * 60 * 1000;
export const MAX_CAPTURE_PIXELS = 250_000_000;
export const MAX_TILE_PIXELS = 32_000_000;
export const MAX_TILES = 1200;

export function validateMetrics(metrics) {
  const values = [metrics?.scrollY, metrics?.scrollX, metrics?.viewportWidth,
    metrics?.viewportHeight, metrics?.documentHeight, metrics?.devicePixelRatio];
  if (!values.every(Number.isFinite) || metrics.viewportWidth <= 0 || metrics.viewportHeight <= 0 ||
      metrics.documentHeight <= 0 || metrics.devicePixelRatio <= 0) {
    throw new Error("invalid_metrics");
  }
  if (metrics.scrollX !== 0) throw new Error("horizontal_scroll_unsupported");
}

export function initialTarget(metrics) {
  validateMetrics(metrics);
  return 0;
}

export function nextTarget(scrollY, documentHeight, viewportHeight, overlap = DEFAULT_OVERLAP) {
  if (![scrollY, documentHeight, viewportHeight, overlap].every(Number.isFinite) ||
      documentHeight < 0 || viewportHeight <= 0 || overlap < 0 || overlap >= 1) {
    throw new Error("invalid_metrics");
  }
  const maxScroll = Math.max(0, documentHeight - viewportHeight);
  if (scrollY >= maxScroll - 0.5) return null;
  const step = viewportHeight * (1 - overlap);
  return Math.min(maxScroll, scrollY + step);
}

export function captureBudget({ documentHeight, viewportWidth, viewportHeight, devicePixelRatio }, tileCount) {
  if (![documentHeight, viewportWidth, viewportHeight, devicePixelRatio].every(Number.isFinite) || documentHeight <= 0 || viewportWidth <= 0 || viewportHeight <= 0 || devicePixelRatio <= 0) {
    throw new Error("invalid_metrics");
  }
  // A tile always contains one full viewport, including the final overlapping bottom tile.
  const physicalTilePixels = Math.ceil(viewportWidth * devicePixelRatio) * Math.ceil(viewportHeight * devicePixelRatio);
  if (physicalTilePixels > MAX_TILE_PIXELS) throw new Error("tile_budget_exceeded");
  const maxScroll = Math.max(0, documentHeight - viewportHeight);
  const step = viewportHeight * (1 - DEFAULT_OVERLAP);
  const projectedTiles = Math.ceil(maxScroll / step) + 1;
  const pixels = physicalTilePixels * projectedTiles;
  if (pixels > MAX_CAPTURE_PIXELS) throw new Error("pixel_budget_exceeded");
  if (Math.max(projectedTiles, tileCount) > MAX_TILES) throw new Error("tile_budget_exceeded");
  return pixels;
}

export function progressPercent(scrollY, viewportHeight, documentHeight) {
  const covered = Math.min(documentHeight, Math.max(0, scrollY + viewportHeight));
  return documentHeight <= 0 ? 100 : Math.min(100, Math.floor((covered / documentHeight) * 100));
}
