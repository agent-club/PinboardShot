import test from "node:test";
import assert from "node:assert/strict";
import vm from "node:vm";
import { readFile } from "node:fs/promises";

const source = await readFile(new URL("../popup.js", import.meta.url), "utf8");

function popup(reply) {
  const elements = new Map();
  let closed = 0;
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
      sendMessage: async message => message.type === "start" ? reply : { ok: false },
      onMessage: { addListener() {} }
    } }
  });
  return { elements, closed: () => closed };
}

test("an accepted capture closes its popup so focus returns to the capture window", async () => {
  const view = popup({ ok: true });
  await view.elements.get("start").handlers.click();
  assert.equal(view.closed(), 1);
});

test("a rejected start keeps the popup open and shows its error", async () => {
  const view = popup({ ok: false, error: "unsupported_page" });
  await view.elements.get("start").handlers.click();
  assert.equal(view.closed(), 0);
  assert.match(view.elements.get("message").textContent, /不支持截图/);
});
