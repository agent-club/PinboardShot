import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

function makeContext() {
  const listeners = [];
  const windowListeners = new Map();
  const properties = new Map();
  const scrollCalls = [];
  const makeStyle = () => ({
    getPropertyValue: name => properties.get(name)?.[0] || "",
    getPropertyPriority: name => properties.get(name)?.[1] || "",
    setProperty: (name, value, priority = "") => properties.set(name, [value, priority]),
    removeProperty: name => properties.delete(name)
  });
  const root = { scrollHeight: 1400, style: makeStyle(), isConnected: true };
  const body = { scrollHeight: 1400, style: makeStyle(), isConnected: true };
  const document = {
    scrollingElement: root,
    documentElement: root,
    body,
    images: [],
    fonts: { ready: Promise.resolve() },
    querySelectorAll: () => []
  };
  const window = {
    innerWidth: 900,
    innerHeight: 600,
    scrollX: 0,
    scrollY: 73,
    addEventListener: (name, fn) => { windowListeners.set(name, (windowListeners.get(name) || 0) + 1); },
    removeEventListener: name => windowListeners.set(name, Math.max(0, (windowListeners.get(name) || 0) - 1)),
    scrollTo: (x, y) => {
      scrollCalls.push({ behavior: root.style.getPropertyValue("scroll-behavior"), snap: root.style.getPropertyValue("scroll-snap-type") });
      window.scrollX = x; window.scrollY = y;
    }
  };
  const chrome = { runtime: {
    id: "extension-id",
    onMessage: { addListener: listener => listeners.push(listener) },
    sendMessage: async () => ({})
  } };
  const context = vm.createContext({
    chrome, document, window,
    globalThis: undefined,
    getComputedStyle: () => ({ position: "static" }),
    requestAnimationFrame: callback => queueMicrotask(callback),
    setTimeout,
    Promise,
    Map,
    Math,
    Date,
    Number,
    Object
  });
  context.globalThis = context;
  return { context, listeners, windowListeners, window, root, scrollCalls };
}

test("re-injecting the content script keeps a single message listener across repeated captures", async () => {
  const { context, listeners, windowListeners, window, root, scrollCalls } = makeContext();
  const source = fs.readFileSync(new URL("../capture.js", import.meta.url), "utf8");
  vm.runInContext(source, context);
  vm.runInContext(source, context);
  assert.equal(listeners.length, 1);
  assert.equal(windowListeners.get("keydown") || 0, 0);

  const api = context.__pinboardShotCapture;
  assert.equal(api.prepare().originalScrollY, 73);
  assert.equal(windowListeners.get("keydown"), 1);
  await api.goTo(400, true);
  api.restore();
  assert.equal(window.scrollY, 73);
  assert.deepEqual(scrollCalls.at(-1), { behavior: "auto", snap: "none" });
  assert.equal(root.style.getPropertyValue("scroll-behavior"), "");
  assert.equal(root.style.getPropertyValue("scroll-snap-type"), "");
  assert.equal(windowListeners.get("keydown"), 0);
  assert.equal(listeners.length, 1);

  api.prepare();
  await api.goTo(800, true);
  api.restore();
  assert.equal(window.scrollY, 73);
  assert.equal(windowListeners.get("keydown"), 0);
  assert.equal(listeners.length, 1);
});

test("scroll replies even when Chrome suspends animation frames", async () => {
  const { context, window } = makeContext();
  context.requestAnimationFrame = () => {};
  vm.runInContext(fs.readFileSync(new URL("../capture.js", import.meta.url), "utf8"), context);
  const api = context.__pinboardShotCapture;
  api.prepare();
  let deadline;
  try {
    const result = await Promise.race([
      api.goTo(400, true),
      new Promise((_, reject) => {
        deadline = setTimeout(() => reject(new Error("scroll blocked by suspended animation frames")), 1500);
      })
    ]);
    assert.equal(result.scrollY, 400);
  } finally {
    clearTimeout(deadline);
    api.restore();
  }
  assert.equal(window.scrollY, 73);
});
