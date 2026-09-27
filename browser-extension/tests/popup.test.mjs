import test from "node:test";
import assert from "node:assert/strict";
import vm from "node:vm";
import { readFile } from "node:fs/promises";

const source = await readFile(new URL("../popup.js", import.meta.url), "utf8");

function popup(reply) {
  const elements = new Map();
  let closed = 0;
  const sentMessages = [];
  let listener;
  const document = {
    documentElement: {},
    getElementById(id) {
      if (!elements.has(id)) elements.set(id, {
        handlers: {}, style: {}, classList: { remove() {}, add() {}, toggle() {} },
        addEventListener(name, handler) { this.handlers[name] = handler; }
      });
      return elements.get(id);
    }
  };
  vm.runInNewContext(source, {
    document, navigator: { language: "zh" }, window: { close() { closed++; } },
    localStorage: { getItem() { return null; }, setItem() {} },
    chrome: { runtime: {
      sendMessage: async message => { sentMessages.push(message); return message.type === "start" ? reply : { ok: true }; },
      onMessage: { addListener(callback) { listener = callback; } }
    } }
  });
  return { elements, closed: () => closed, sentMessages,
    state: state => listener({ channel: "pinboardshot.capture", type: "state", state }) };
}

test("an accepted manual capture keeps its side panel open", async () => {
  const view = popup({ ok: true });
  await view.elements.get("start").handlers.click();
  assert.equal(view.closed(), 0);
});

test("a rejected start keeps the popup open and shows its error", async () => {
  const view = popup({ ok: false, error: "unsupported_page" });
  await view.elements.get("start").handlers.click();
  assert.equal(view.closed(), 0);
  assert.match(view.elements.get("message").textContent, /不支持截图/);
});

test("popup exposes pause, resume, and stop controls for an active capture", async () => {
  const view = popup({ ok: true });
  await view.elements.get("pause").handlers.click();
  await view.elements.get("stop").handlers.click();
  assert.ok(view.sentMessages.some(message => message.type === "togglePause"));
  assert.ok(view.sentMessages.some(message => message.type === "stop"));
});

test("panel shows acknowledged pause and resume states and keeps stop available while paused", async () => {
  const view = popup({ ok: true });
  await Promise.resolve();
  view.state({ status: "capturing", progress: 42 });
  assert.equal(view.elements.get("start").hidden, true);
  assert.equal(view.elements.get("progressPercent").textContent, "42%");
  assert.equal(view.elements.get("pause").textContent, "暂停截图");
  view.state({ status: "pausing", progress: 42 });
  assert.equal(view.elements.get("pause").disabled, true);
  view.state({ status: "paused", progress: 42 });
  assert.equal(view.elements.get("pause").textContent, "继续截图");
  assert.equal(view.elements.get("pause").disabled, false);
  assert.equal(view.elements.get("stop").hidden, false);
  assert.equal(view.elements.get("finishHint").hidden, false);
  view.state({ status: "stopping", progress: 42 });
  assert.equal(view.elements.get("stop").disabled, true);
  view.state({ status: "stopped", progress: 42 });
  assert.equal(view.elements.get("start").hidden, false);
  assert.equal(view.elements.get("stop").hidden, true);
  assert.match(view.elements.get("progressText").textContent, /已保留/);
});
