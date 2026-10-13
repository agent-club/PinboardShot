import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

function makeContext() {
  const listeners = [];
  const windowListeners = new Map();
  const scrollCalls = [];
  const makeStyle = () => {
    const properties = new Map();
    return {
      getPropertyValue: name => properties.get(name)?.[0] || "",
      getPropertyPriority: name => properties.get(name)?.[1] || "",
      setProperty: (name, value, priority = "") => properties.set(name, [value, priority]),
      removeProperty: name => properties.delete(name)
    };
  };
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
    clearTimeout,
    Promise,
    Map,
    Math,
    Date,
    Number,
    Object
  });
  context.globalThis = context;
  return { context, listeners, windowListeners, window, root, scrollCalls, document, makeStyle };
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

test("sticky headings below the first viewport remain in flow and restore their original styles", async () => {
  const { context, document, makeStyle } = makeContext();
  const heading = { style: makeStyle(), isConnected: true };
  heading.style.setProperty("position", "sticky", "important");
  heading.style.setProperty("top", "20px");
  document.querySelectorAll = () => [heading];
  context.getComputedStyle = element => ({ position: element.style.getPropertyValue("position") || "static" });
  vm.runInContext(fs.readFileSync(new URL("../capture.js", import.meta.url), "utf8"), context);
  const api = context.__pinboardShotCapture;
  api.prepare();
  await api.goTo(800, true);
  assert.equal(heading.style.getPropertyValue("visibility"), "");
  assert.equal(heading.style.getPropertyValue("position"), "relative");
  assert.equal(heading.style.getPropertyValue("top"), "auto");
  api.restore();
  assert.equal(heading.style.getPropertyValue("position"), "sticky");
  assert.equal(heading.style.getPropertyPriority("position"), "important");
  assert.equal(heading.style.getPropertyValue("top"), "20px");
  assert.equal(heading.style.getPropertyValue("left"), "");
});

test("a visible image decode failure prevents a successful tile", async () => {
  const { context, document } = makeContext();
  document.images = [{ complete: false, decode: async () => { throw new Error("network"); },
    getBoundingClientRect: () => ({ top: 20, bottom: 120, left: 20, right: 120, width: 100, height: 100 }) }];
  vm.runInContext(fs.readFileSync(new URL("../capture.js", import.meta.url), "utf8"), context);
  context.__pinboardShotCapture.prepare();
  await assert.rejects(context.__pinboardShotCapture.goTo(0, false), /visible_resource_failed/);
  context.__pinboardShotCapture.restore();
});

test("a visible resource timeout is reported rather than committing a blank tile", async () => {
  const { context, document } = makeContext();
  document.images = [{ complete: false, decode: () => new Promise(() => {}),
    getBoundingClientRect: () => ({ top: 20, bottom: 120, left: 20, right: 120, width: 100, height: 100 }) }];
  context.setTimeout = (callback, delay) => setTimeout(callback, delay === 5000 ? 5 : delay);
  vm.runInContext(fs.readFileSync(new URL("../capture.js", import.meta.url), "utf8"), context);
  context.__pinboardShotCapture.prepare();
  await assert.rejects(context.__pinboardShotCapture.goTo(0, false), /visible_resource_timeout/);
  context.__pinboardShotCapture.restore();
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
