import test from "node:test";
import assert from "node:assert/strict";

const settle = () => new Promise(resolve => setTimeout(resolve, 0));

function makeChrome({ switchAfterFirstImage = false, moveAfterFirstImage = false, finishOpenFailed = false,
  windowFocused = true, supportsCaptureControl = true, pauseAfterFirstTile = false,
  pauseBeforeSecondTile = false, documentHeight = 1500, viewportHeight = 500,
  hideTabURL = false, hangVisibleCapture = false, hangMetrics = false } = {}) {
  const runtimeMessages = [];
  const nativeRequests = [];
  const contentRequests = [];
  const openedPanels = [];
  const listeners = { runtime: [], commands: [], action: [] };
  const native = { message: [], disconnect: [] };
  let scrollY = 0;
  let active = true;
  let imageCount = 0;
  let restored = false;
  let injected = false;
  let controlPaused = false;
  let controlStopped = false;
  let pauseRequested = false;
  let tabId = 40;
  let windowId = 7;
  const page = { viewportWidth: 800, viewportHeight, documentHeight, devicePixelRatio: 1 };
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
              if (message.command === "tileEnd" && message.index === 0 && pauseAfterFirstTile) controlPaused = true;
              if (message.command === "setControl") {
                controlPaused = message.paused;
                controlStopped ||= message.stopped;
              }
              const reply = { requestId: message.requestId, ok: !(finishOpenFailed && message.command === "finish"),
                ...(message.command === "hello" ? { protocolVersion: 1, maxChunkBytes: 64, ...(supportsCaptureControl ? { supportsCaptureControl: true } : {}) } : {}),
                ...(message.command === "begin" ? { captureId: "capture-test" } : {}),
                ...(message.command === "control" ? { paused: controlPaused, stopped: controlStopped } : {}),
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
    sidePanel: { open: async options => { openedPanels.push(options); } },
    commands: { onCommand: { addListener: fn => listeners.commands.push(fn) } },
    windows: { getLastFocused: async () => ({ id: windowId, focused: active && windowFocused, tabs: [{ id: tabId, windowId, active }] }) },
    tabs: {
      query: async () => [{ id: tabId, windowId, active: true,
        ...(!hideTabURL ? { url: "https://example.test/article" } : {}) }],
      captureVisibleTab: async requestedWindow => {
        assert.equal(requestedWindow, windowId);
        imageCount++;
        if (hangVisibleCapture) return new Promise(() => {});
        const image = `data:image/png;base64,${"A".repeat(100)}`;
        if (switchAfterFirstImage && imageCount === 1) active = false;
        if (moveAfterFirstImage && imageCount === 1) scrollY += 17;
        return image;
      },
      sendMessage: async (id, message) => {
        contentRequests.push(message);
        assert.equal(id, 40);
        if (message.type === "prepare") return { ok: true, metrics: { ...page, scrollX: 0, scrollY, originalScrollY: 73 } };
        if (message.type === "goTo") {
          if (pauseBeforeSecondTile && !pauseRequested && message.targetY > 0) {
            pauseRequested = true;
            controlPaused = true;
          }
          scrollY = Math.min(message.targetY, page.documentHeight - page.viewportHeight);
          return { ok: true, metrics: { ...page, scrollX: 0, scrollY } };
        }
        if (message.type === "metrics") {
          if (hangMetrics) return new Promise(() => {});
          return { ok: true, metrics: { ...page, scrollX: 0, scrollY } };
        }
        if (message.type === "restore") { scrollY = 73; restored = true; return { ok: true, restored: true }; }
        throw new Error(`Unexpected content message: ${message.type}`);
      }
    },
    scripting: { executeScript: async () => { injected = true; return []; } }
  };
  return { chrome, listeners, runtimeMessages, nativeRequests, openedPanels,
    setPaused(value) { controlPaused = value; }, setStopped(value) { controlStopped = value; },
    setPageScroll(value) { scrollY = value; },
    inspect: () => ({ scrollY, active, imageCount, restored, injected, contentRequests: [...contentRequests] }) };
}

const popupSender = { id: "extension-id", url: "chrome-extension://extension-id/popup.html" };
const waitUntil = async (predicate, limit = 12000) => {
  for (let attempt = 0; attempt < limit; attempt++) {
    if (predicate()) return true;
    await settle();
  }
  return false;
};
const startCapture = mock => new Promise(resolve => mock.listeners.runtime[0](
  { channel: "pinboardshot.capture", type: "start" }, popupSender, resolve));

async function loadBackground(mock) {
  globalThis.chrome = mock.chrome;
  const url = new URL(`../background.js?test=${Math.random()}`, import.meta.url);
  await import(url.href);
}

test("only a manual toolbar click opens the persistent control panel", async () => {
  const mock = makeChrome();
  await loadBackground(mock);
  mock.listeners.action[0]({ id: 40, windowId: 7 });
  await settle();
  assert.deepEqual(mock.openedPanels, [{ windowId: 7 }]);
  assert.equal(mock.nativeRequests.length, 0);
});

test("a side panel carried to a tab without activeTab access asks for a toolbar click", async () => {
  const mock = makeChrome({ hideTabURL: true });
  await loadBackground(mock);
  const reply = await startCapture(mock);
  assert.deepEqual(reply, { ok: false, error: "invoke_on_current_tab" });
  assert.equal(mock.nativeRequests.length, 0);
});

test("cancel releases a capture when Chrome never returns its first screenshot", async () => {
  const mock = makeChrome({ hangVisibleCapture: true });
  await loadBackground(mock);
  assert.equal((await startCapture(mock)).ok, true);
  assert.ok(await waitUntil(() => mock.inspect().imageCount === 1));
  await new Promise(resolve => mock.listeners.runtime[0](
    { channel: "pinboardshot.capture", type: "cancel" }, popupSender, resolve));
  assert.ok(await waitUntil(() => mock.runtimeMessages.some(message => message.state?.status === "cancelled")));
  assert.equal(mock.inspect().restored, true);
  assert.ok(mock.nativeRequests.some(request => request.command === "cancel"));
});

test("cancel releases a capture when the page stops replying to metrics", async () => {
  const mock = makeChrome({ hangMetrics: true });
  await loadBackground(mock);
  assert.equal((await startCapture(mock)).ok, true);
  assert.ok(await waitUntil(() => mock.inspect().contentRequests.some(message => message.type === "metrics")));
  await new Promise(resolve => mock.listeners.runtime[0](
    { channel: "pinboardshot.capture", type: "cancel" }, popupSender, resolve));
  assert.ok(await waitUntil(() => mock.runtimeMessages.some(message => message.state?.status === "cancelled")));
  assert.equal(mock.inspect().restored, true);
  assert.ok(mock.nativeRequests.some(request => request.command === "cancel"));
});

test("the App shortcut captures without opening an extension panel", async () => {
  const mock = makeChrome();
  await loadBackground(mock);
  mock.listeners.commands[0]("start-long-screenshot");
  assert.ok(await waitUntil(() => mock.runtimeMessages.some(message => message.state?.status === "complete")));
  assert.deepEqual(mock.openedPanels, []);
  assert.ok(mock.nativeRequests.some(request => request.command === "finish"));
});

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
  const { contentRequests, ...capture } = mock.inspect();
  assert.deepEqual(capture, { scrollY: 73, active: true, imageCount: 4, restored: true, injected: true });
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

test("native hosts without capture-control support fail with a clear protocol error", async () => {
  const mock = makeChrome({ supportsCaptureControl: false });
  await loadBackground(mock);
  await startCapture(mock);
  assert.equal(await waitUntil(() => mock.runtimeMessages.some(item => item.state?.status === "error")), true);
  assert.ok(mock.runtimeMessages.some(item => item.state?.error === "native_protocol_unsupported"));
  assert.equal(mock.inspect().imageCount, 0);
});

test("pause blocks further scrolling and tiles; resume restores the next tile coordinate", async () => {
  const mock = makeChrome({ pauseAfterFirstTile: true });
  await loadBackground(mock);
  await startCapture(mock);
  assert.equal(await waitUntil(() => mock.runtimeMessages.some(item => item.state?.status === "paused")), true);
  assert.equal(mock.inspect().imageCount, 1);
  assert.deepEqual(mock.inspect().contentRequests.filter(item => item.type === "goTo").map(item => item.targetY), [0]);
  mock.setPageScroll(733);
  await new Promise(resolve => setTimeout(resolve, 700));
  assert.equal(mock.inspect().imageCount, 1);
  assert.deepEqual(mock.inspect().contentRequests.filter(item => item.type === "goTo").map(item => item.targetY), [0]);

  mock.setPaused(false);
  assert.equal(await waitUntil(() => mock.runtimeMessages.some(item => item.state?.status === "complete")), true);
  const tilePositions = mock.nativeRequests.filter(item => item.command === "tileBegin").map(item => item.scrollY);
  assert.deepEqual(tilePositions, [0, 425, 850, 1000]);
  const goToPositions = mock.inspect().contentRequests.filter(item => item.type === "goTo").map(item => item.targetY);
  assert.deepEqual(goToPositions, [0, 425, 850, 1000]);
});

test("pause before a tile restores its target after the user moves the page", async () => {
  const mock = makeChrome({ pauseBeforeSecondTile: true });
  await loadBackground(mock);
  await startCapture(mock);
  assert.equal(await waitUntil(() => mock.runtimeMessages.some(item => item.state?.status === "paused")), true);
  assert.equal(mock.inspect().imageCount, 1);
  mock.setPageScroll(733);
  await new Promise(resolve => setTimeout(resolve, 700));
  assert.equal(mock.inspect().imageCount, 1);
  assert.deepEqual(mock.inspect().contentRequests.filter(item => item.type === "goTo").map(item => item.targetY), [0, 425]);

  mock.setPaused(false);
  assert.equal(await waitUntil(() => mock.runtimeMessages.some(item => item.state?.status === "complete")), true);
  const tilePositions = mock.nativeRequests.filter(item => item.command === "tileBegin").map(item => item.scrollY);
  assert.deepEqual(tilePositions, [0, 425, 850, 1000]);
  const goToPositions = mock.inspect().contentRequests.filter(item => item.type === "goTo").map(item => item.targetY);
  assert.deepEqual(goToPositions, [0, 425, 425, 850, 1000]);
});

test("stopping while paused saves complete tiles as a partial image", async () => {
  const mock = makeChrome({ pauseAfterFirstTile: true });
  await loadBackground(mock);
  await startCapture(mock);
  assert.equal(await waitUntil(() => mock.runtimeMessages.some(item => item.state?.status === "paused")), true);
  mock.setStopped(true);
  assert.equal(await waitUntil(() => mock.runtimeMessages.some(item => item.state?.status === "stopped")), true);
  assert.ok(mock.nativeRequests.some(item => item.command === "finish" && item.capturedHeight === 500));
  assert.ok(!mock.nativeRequests.some(item => item.command === "cancel"));
  assert.equal(mock.inspect().imageCount, 1);
});

test("partial stop caps covered height at the last committed tile document height", async () => {
  const mock = makeChrome({ pauseAfterFirstTile: true, documentHeight: 300, viewportHeight: 500 });
  await loadBackground(mock);
  await startCapture(mock);
  assert.equal(await waitUntil(() => mock.runtimeMessages.some(item => item.state?.status === "paused")), true);
  const stopReply = await new Promise(resolve => mock.listeners.runtime[0](
    { channel: "pinboardshot.capture", type: "stop" }, popupSender, resolve));
  assert.equal(stopReply.ok, true);
  assert.equal(await waitUntil(() => mock.runtimeMessages.some(item => item.state?.status === "stopped")), true);
  assert.ok(mock.nativeRequests.some(item => item.command === "setControl" && item.paused === true && item.stopped === true));
  assert.ok(mock.nativeRequests.some(item => item.command === "finish" && item.capturedHeight === 300));
});

test("cancelling while paused discards the capture and wakes the paused loop", async () => {
  const mock = makeChrome({ pauseAfterFirstTile: true });
  await loadBackground(mock);
  await startCapture(mock);
  assert.equal(await waitUntil(() => mock.runtimeMessages.some(item => item.state?.status === "paused")), true);
  await new Promise(resolve => mock.listeners.runtime[0]({ channel: "pinboardshot.capture", type: "cancel" }, popupSender, resolve));
  assert.equal(await waitUntil(() => mock.runtimeMessages.some(item => item.state?.status === "cancelled")), true);
  assert.ok(mock.nativeRequests.some(item => item.command === "cancel"));
  assert.ok(!mock.nativeRequests.some(item => item.command === "finish"));
});

test("App control requests are polled with capture identity, status, and integer progress", async () => {
  const mock = makeChrome();
  await loadBackground(mock);
  await startCapture(mock);
  assert.equal(await waitUntil(() => mock.runtimeMessages.some(item => item.state?.status === "complete")), true);
  const controls = mock.nativeRequests.filter(item => item.command === "control");
  assert.ok(controls.length > 0);
  assert.ok(controls.every(item => item.captureId === "capture-test" &&
    ["preparing", "capturing", "pausing", "paused", "stopping"].includes(item.status) &&
    Number.isInteger(item.progress) && item.progress >= 0 && item.progress <= 100));
});


test("popup pause writes shared native desired state and App resume is observed", async () => {
  const mock = makeChrome();
  await loadBackground(mock);
  await startCapture(mock);
  assert.equal(await waitUntil(() => mock.inspect().imageCount >= 1), true);
  const toggleReply = await new Promise(resolve => mock.listeners.runtime[0](
    { channel: "pinboardshot.capture", type: "togglePause" }, popupSender, resolve));
  assert.equal(toggleReply.ok, true);
  assert.equal(await waitUntil(() => mock.runtimeMessages.some(item => item.state?.status === "paused")), true);
  assert.ok(mock.nativeRequests.some(item => item.command === "setControl" && item.paused === true && item.stopped === false));

  mock.setPaused(false);
  assert.equal(await waitUntil(() => mock.runtimeMessages.some(item => item.state?.status === "complete")), true);
  assert.deepEqual(mock.nativeRequests.filter(item => item.command === "tileBegin").map(item => item.scrollY), [0, 425, 850, 1000]);
});
