import test from "node:test";
import assert from "node:assert/strict";
import { captureBudget, MAX_CAPTURE_PIXELS, MAX_TILE_PIXELS, nextTarget, progressPercent, validateMetrics } from "../lib/planner.mjs";

test("plans overlapping positions from actual page coordinates and reaches the last viewport", () => {
  const positions = [0];
  let y = 0;
  while ((y = nextTarget(y, 1800, 600)) !== null) positions.push(y);
  assert.deepEqual(positions, [0, 510, 1020, 1200]);
  assert.ok(positions.slice(1).every((value, index) => value <= positions[index] + 600));
});

test("recomputes the next target after the document grows", () => {
  assert.equal(nextTarget(600, 1000, 400), null);
  assert.equal(nextTarget(600, 1700, 400), 940);
});

test("rejects invalid and horizontally scrolled page geometry", () => {
  assert.throws(() => validateMetrics({ scrollX: 2, scrollY: 0, viewportWidth: 10, viewportHeight: 10, documentHeight: 10, devicePixelRatio: 1 }), /horizontal_scroll_unsupported/);
  assert.throws(() => nextTarget(Number.NaN, 10, 10), /invalid_metrics/);
});

test("enforces physical-pixel and tile budgets and reports coverage progress", () => {
  assert.equal(captureBudget({ documentHeight: 1000, viewportWidth: 1000, viewportHeight: 500, devicePixelRatio: 2 }, 3), 6_000_000);
  assert.throws(() => captureBudget({ documentHeight: 1_000_000, viewportWidth: 1100, viewportHeight: 1000, devicePixelRatio: 2 }, 1), /pixel_budget_exceeded/);
  assert.throws(() => captureBudget({ documentHeight: 10000, viewportWidth: MAX_TILE_PIXELS / 2 + 1, viewportHeight: 1, devicePixelRatio: 2 }, 1), /tile_budget_exceeded/);
  assert.throws(() => validateMetrics({ scrollX: 0, scrollY: 0, viewportWidth: 10, viewportHeight: 10, documentHeight: 0, devicePixelRatio: 1 }), /invalid_metrics/);
  assert.equal(progressPercent(850, 300, 1000), 100);
});
