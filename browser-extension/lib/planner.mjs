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

export function captureBudget({ documentHeight, viewportWidth, viewportHeight, devicePixelRatio, requiredOverlap = DEFAULT_OVERLAP }, tileCount) {
  if (![documentHeight, viewportWidth, viewportHeight, devicePixelRatio].every(Number.isFinite) || documentHeight <= 0 || viewportWidth <= 0 || viewportHeight <= 0 || devicePixelRatio <= 0) {
    throw new Error("invalid_metrics");
  }
  // A tile always contains one full viewport, including the final overlapping bottom tile.
  const physicalTilePixels = Math.ceil(viewportWidth * devicePixelRatio) * Math.ceil(viewportHeight * devicePixelRatio);
  if (physicalTilePixels > MAX_TILE_PIXELS) throw new Error("tile_budget_exceeded");
  const maxScroll = Math.max(0, documentHeight - viewportHeight);
  if (!Number.isFinite(requiredOverlap) || requiredOverlap < DEFAULT_OVERLAP || requiredOverlap >= 0.9) throw new Error("invalid_metrics");
  const step = viewportHeight * (1 - requiredOverlap);
  const projectedTiles = Math.ceil(maxScroll / step) + 1;
  const pixels = physicalTilePixels * projectedTiles;
  if (pixels > MAX_CAPTURE_PIXELS) throw new Error("pixel_budget_exceeded");
  if (Math.max(projectedTiles, tileCount) > MAX_TILES) throw new Error("tile_budget_exceeded");
  return pixels;
}

export function tileCropRect(metrics, imageWidth, imageHeight) {
  const rect = metrics.captureRect;
  const browserWidth = metrics.browserViewportWidth;
  const browserHeight = metrics.browserViewportHeight;
  if (![rect?.x, rect?.y, rect?.width, rect?.height, browserWidth, browserHeight, imageWidth, imageHeight].every(Number.isFinite) ||
      rect.x < 0 || rect.y < 0 || rect.width <= 0 || rect.height <= 0 || browserWidth <= 0 || browserHeight <= 0 ||
      imageWidth <= 0 || imageHeight <= 0 || rect.x + rect.width > browserWidth + 0.5 || rect.y + rect.height > browserHeight + 0.5) {
    throw new Error("invalid_crop_geometry");
  }
  // Use the PNG's actual scale, not an assumed Retina factor or browser zoom.
  const scale = imageWidth / browserWidth;
  if (Math.abs(imageHeight - browserHeight * scale) > 1.1) throw new Error("invalid_crop_geometry");
  const result = { x: Math.round(rect.x * scale), y: Math.round(rect.y * scale),
    width: Math.round(rect.width * scale), height: Math.round(rect.height * scale) };
  if (result.width <= 0 || result.height <= 0 || result.x + result.width > imageWidth || result.y + result.height > imageHeight) {
    throw new Error("invalid_crop_geometry");
  }
  return result;
}

export function progressPercent(scrollY, viewportHeight, documentHeight) {
  const covered = Math.min(documentHeight, Math.max(0, scrollY + viewportHeight));
  return documentHeight <= 0 ? 100 : Math.min(100, Math.floor((covered / documentHeight) * 100));
}
