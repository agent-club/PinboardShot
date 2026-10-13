import test from "node:test";
import assert from "node:assert/strict";
import { saveBrowserCapture } from "../lib/browser-download.mjs";

const tick = () => new Promise(resolve => setImmediate(resolve));
function downloads({ reject, state = "in_progress", pending = false, fast = false } = {}) {
  const listeners = new Set();
  const requests = [];
  const cancels = [];
  let returnId;
  const chrome = { downloads: {
    onChanged: { addListener: callback => listeners.add(callback), removeListener: callback => listeners.delete(callback) },
    download(options) {
      requests.push(options);
      if (reject) return Promise.reject(new Error(reject));
      if (fast) for (const listener of listeners) listener({ id: 12, state: { current: "complete" } });
      return pending ? new Promise(resolve => { returnId = resolve; }) : Promise.resolve(12);
    },
    search: async query => { assert.deepEqual(query, { id: 12 }); return [{ id: 12, state, error: state === "interrupted" ? "NETWORK_FAILED" : undefined }]; },
    cancel: async id => { cancels.push(id); }
  } };
  return { chrome, requests, cancels, listeners, returnId: () => returnId(12),
    changed(id, state, error) { for (const listener of listeners) listener({ id, state: { current: state }, error: { current: error } }); } };
}
const png = () => new Blob([new Uint8Array([137, 80, 78, 71])], { type: "image/png" });

test("saving waits for its own completed download and passes the save location choice", async () => {
  const mock = downloads();
  let complete = false;
  const result = saveBrowserCapture(mock.chrome, png(), { saveAs: true }).then(id => { complete = true; return id; });
  await tick();
  assert.equal(complete, false);
  assert.equal(mock.requests[0].saveAs, true);
  assert.match(mock.requests[0].filename, /^PinboardShot-.*\.png$/);
  assert.equal(mock.requests[0].url, "data:image/png;base64,iVBORw==");
  mock.changed(99, "complete");
  await tick();
  assert.equal(complete, false);
  mock.changed(12, "complete");
  assert.equal(await result, 12);
  assert.equal(mock.listeners.size, 0);
  assert.deepEqual(mock.cancels, []);
});

test("the own-ID query observes completion that preceded download ID delivery", async () => {
  const mock = downloads({ fast: true, state: "complete" });
  assert.equal(await saveBrowserCapture(mock.chrome, png()), 12);
  assert.equal(mock.requests[0].saveAs, false);
  assert.equal(mock.listeners.size, 0);
});

test("an interrupted save reports failure and cleans up its listener", async () => {
  const mock = downloads();
  const result = saveBrowserCapture(mock.chrome, png());
  const failed = assert.rejects(result, /browser_download_failed/);
  await tick();
  mock.changed(12, "interrupted", "FILE_FAILED");
  await failed;
  assert.equal(mock.listeners.size, 0);
});

test("cancel before a delayed save dialog returns cancels only the returned download", async () => {
  const mock = downloads({ pending: true });
  const controller = new AbortController();
  const result = saveBrowserCapture(mock.chrome, png(), { signal: controller.signal });
  const cancelled = assert.rejects(result, /cancelled/);
  await tick();
  controller.abort();
  await cancelled;
  mock.returnId();
  await tick();
  assert.deepEqual(mock.cancels, [12]);
  assert.equal(mock.listeners.size, 0);
});

test("download rejection or timeout never claims the PNG was saved", async () => {
  const rejected = downloads({ reject: "User canceled" });
  await assert.rejects(saveBrowserCapture(rejected.chrome, png()), /cancelled/);
  assert.equal(rejected.listeners.size, 0);
  const timedOut = downloads({ pending: true });
  await assert.rejects(saveBrowserCapture(timedOut.chrome, png(), { timeoutMs: 5 }), /browser_download_timeout/);
  timedOut.returnId();
  await tick();
  assert.deepEqual(timedOut.cancels, [12]);
  assert.equal(timedOut.listeners.size, 0);
});
