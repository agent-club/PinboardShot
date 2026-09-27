import test from "node:test";
import assert from "node:assert/strict";

const settle = () => new Promise(resolve => setTimeout(resolve, 0));

function makeChrome({ switchAfterFirstImage = false, moveAfterFirstImage = false, finishOpenFailed = false, windowFocused = true } = {}) {
  const runtimeMessages = [];
  const nativeRequests = [];
  const listeners = { runtime: [], commands: [], action: [] };
  const native = { message: [], disconnect: [] };
  let scrollY = 0;
  let active = true;
  let imageCount = 0;
  let restored = false;
  let injected = false;
  let tabId = 40;
  let windowId = 7;
  const page = { viewportWidth: 800, viewportHeight: 500, documentHeight: 1500, devicePixelRatio: 1 };
  const chrome = {
    runtime: {
      id: "extension-id",
      lastError: null,
      id: "extension-id",
      getURL: path => `chrome-extension://extension-id/${path}`,
      onMessage: { addListener: fn => listeners.runtime.push(fn) },
      sendMessage: async message => { runtimeMessages.push(message); return {}; },
      connectNative: host => {
        assert.equal(host, "com.ryanwang.pinboardshot.browser_capture");
        const port = {
          onMessage: { addListener: fn => native.message.push(fn) },
          onDisconnect: { addListener: fn => native.disconnect.push(fn) },
          postMessage: message => {
            nativeRequests.push(message);
            queueMicrotask(() => {
              const reply = { requestId: message.requestId, ok: !(finishOpenFailed && message.command === "finish"),
                ...(message.command === "hello" ? { protocolVersion: 1, maxChunkBytes: 64 } : {}),
                ...(message.command === "begin" ? { captureId: "capture-test" } : {}),
                ...(finishOpenFailed && message.command === "finish" ? { error: "app_open_failed", captureSaved: true } : {}) };
              for (const callback of native.message) callback(reply);
            });
          },
          disconnect: () => {}
        };
        return port;
      }
    },
    action: { onClicked: { addListener: fn => listeners.action.push(fn) } },
    commands: { onCommand: { addListener: fn => listeners.commands.push(fn) } },
    windows: { getLastFocused: async () => ({ id: windowId, focused: active && windowFocused, tabs: [{ id: tabId, windowId, active }] }) },
    tabs: {
      query: async () => [{ id: tabId, windowId, active: true, url: "https://example.test/article" }],
      captureVisibleTab: async requestedWindow => {
        assert.equal(requestedWindow, windowId);
        imageCount++;
        const image = `data:image/png;base64,${"A".repeat(100)}`;
        if (switchAfterFirstImage && imageCount === 1) active = false;
        if (moveAfterFirstImage && imageCount === 1) scrollY += 17;
        return image;
      },
      sendMessage: async (id, message) => {
        assert.equal(id, 40);
        if (message.type === "prepare") return { ok: true, metrics: { ...page, scrollX: 0, scrollY, originalScrollY: 73 } };
        if (message.type === "goTo") {
          scrollY = Math.min(message.targetY, page.documentHeight - page.viewportHeight);
          return { ok: true, metrics: { ...page, scrollX: 0, scrollY } };
        }
        if (message.type === "metrics") return { ok: true, metrics: { ...page, scrollX: 0, scrollY } };
        if (message.type === "restore") { scrollY = 73; restored = true; return { ok: true, restored: true }; }
        throw new Error(`Unexpected content message: ${message.type}`);
      }
    },
    scripting: { executeScript: async () => { injected = true; return []; } }
  };
  return { chrome, listeners, runtimeMessages, nativeRequests, inspect: () => ({ scrollY, active, imageCount, restored, injected }) };
}

async function loadBackground(mock) {
  globalThis.chrome = mock.chrome;
  const url = new URL(`../background.js?test=${Math.random()}`, import.meta.url);
  await import(url.href);
}

test("mock Chrome capture streams unique CSS-coordinate tiles and restores the original page", async () => {
  const mock = makeChrome();
  await loadBackground(mock);
  const sender = { id: "extension-id", url: "chrome-extension://extension-id/popup.html" };
  const reply = await new Promise(resolve => mock.listeners.runtime[0]({ channel: "pinboardshot.capture", type: "start" }, sender, resolve));
  assert.equal(reply.ok, true);
  for (let attempt = 0; attempt < 8000 && !mock.runtimeMessages.some(message => message.type === "state" && message.state.status === "complete"); attempt++) await settle();

  const requests = mock.nativeRequests;
  const begins = requests.filter(item => item.command === "tileBegin");
  const chunks = requests.filter(item => item.command === "tileChunk");
  const ends = requests.filter(item => item.command === "tileEnd");
  assert.deepEqual(begins.map(item => item.scrollY), [0, 425, 850, 1000]);
  assert.deepEqual(ends.map(item => item.index), [0, 1, 2, 3]);
  assert.ok(chunks.every(item => item.data.length <= 64));
  assert.ok(requests.some(item => item.command === "finish" && item.capturedHeight === 1500));
  assert.ok(!requests.some(item => item.command === "cancel"));
  assert.deepEqual(mock.inspect(), { scrollY: 73, active: true, imageCount: 4, restored: true, injected: true });
});

test("a popup or another application taking OS focus does not cancel the same Chrome tab", async () => {
  const mock = makeChrome({ windowFocused: false });
  await loadBackground(mock);
  await new Promise(resolve => mock.listeners.runtime[0]({ channel: "pinboardshot.capture", type: "start" }, { id: "extension-id", url: "chrome-extension://extension-id/popup.html" }, resolve));
  for (let attempt = 0; attempt < 8000 && !mock.runtimeMessages.some(message => message.type === "state" && message.state.status === "complete"); attempt++) await settle();
  assert.ok(mock.nativeRequests.some(item => item.command === "finish"));
  assert.equal(mock.inspect().imageCount, 4);
  assert.equal(mock.inspect().restored, true);
  assert.ok(!mock.nativeRequests.some(item => item.command === "cancel"));
});

test("mock Chrome active-tab changes cancel rather than capture another page", async () => {
  const mock = makeChrome({ switchAfterFirstImage: true });
  await loadBackground(mock);
  await new Promise(resolve => mock.listeners.runtime[0]({ channel: "pinboardshot.capture", type: "start" }, { id: "extension-id", url: "chrome-extension://extension-id/popup.html" }, resolve));
  for (let attempt = 0; attempt < 8000 && !mock.runtimeMessages.some(message => message.type === "state" && message.state.status === "error"); attempt++) await settle();
  assert.equal(mock.inspect().imageCount, 1);
  assert.equal(mock.inspect().restored, true);
  assert.ok(mock.nativeRequests.some(item => item.command === "cancel"));
  assert.ok(mock.runtimeMessages.some(item => item.type === "state" && item.state.error === "active_tab_changed"));
});

test("mock Chrome rejects stale tile coordinates if the page moves during screenshot capture", async () => {
  const mock = makeChrome({ moveAfterFirstImage: true });
  await loadBackground(mock);
  await new Promise(resolve => mock.listeners.runtime[0]({ channel: "pinboardshot.capture", type: "start" }, { id: "extension-id", url: "chrome-extension://extension-id/popup.html" }, resolve));
  for (let attempt = 0; attempt < 8000 && !mock.runtimeMessages.some(message => message.type === "state" && message.state.status === "error"); attempt++) await settle();
  assert.equal(mock.inspect().imageCount, 1);
  assert.equal(mock.inspect().restored, true);
  assert.ok(!mock.nativeRequests.some(item => item.command === "tileBegin"));
  assert.ok(mock.nativeRequests.some(item => item.command === "cancel"));
  assert.ok(mock.runtimeMessages.some(item => item.type === "state" && item.state.error === "capture_position_changed"));
});

test("content contexts cannot issue popup start commands", async () => {
  const mock = makeChrome();
  await loadBackground(mock);
  let replied = false;
  mock.listeners.runtime[0]({ channel: "pinboardshot.capture", type: "start" }, { id: "extension-id", tab: { id: 40 }, frameId: 0 }, () => { replied = true; });
  await settle();
  assert.equal(replied, false);
  assert.equal(mock.nativeRequests.length, 0);
  assert.equal(mock.inspect().imageCount, 0);
});

test("saved captures remain intact when the host cannot open the App", async () => {
  const mock = makeChrome({ finishOpenFailed: true });
  await loadBackground(mock);
  await new Promise(resolve => mock.listeners.runtime[0]({ channel: "pinboardshot.capture", type: "start" }, { id: "extension-id", url: "chrome-extension://extension-id/popup.html" }, resolve));
  for (let attempt = 0; attempt < 8000 && !mock.runtimeMessages.some(message => message.type === "state" && message.state.status === "error"); attempt++) await settle();
  assert.ok(mock.nativeRequests.some(item => item.command === "finish"));
  assert.ok(!mock.nativeRequests.some(item => item.command === "cancel"));
  assert.ok(mock.runtimeMessages.some(item => item.type === "state" && item.state.error === "capture_saved_app_open_failed"));
  assert.equal(mock.inspect().restored, true);
});
