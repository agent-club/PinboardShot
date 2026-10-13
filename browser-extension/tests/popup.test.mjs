import test from "node:test";
import assert from "node:assert/strict";
import vm from "node:vm";
import { readFile } from "node:fs/promises";

const source = await readFile(new URL("../popup.js", import.meta.url), "utf8");

function popup(reply, connection = { status: "connected" }, options = {}) {
  const elements = new Map();
  let closed = 0;
  const sentMessages = [];
  let listener;
  let retry;
  const document = {
    documentElement: {},
    getElementById(id) {
      if (!elements.has(id)) elements.set(id, {
        handlers: {}, style: {}, attributes: {}, classList: { remove() {}, add() {}, toggle() {} },
        get textContent() { const label = { start: "startLabel", pause: "pauseLabel", stop: "stopLabel" }[id]; return label ? elements.get(label)?.textContent : this.text; },
        set textContent(value) { this.text = value; },
        setAttribute(name, value) { this.attributes[name] = value; },
        addEventListener(name, handler) { this.handlers[name] = handler; }
      });
      return elements.get(id);
    }
  };
  vm.runInNewContext(source, {
    document, navigator: { language: "zh" }, window: { close() { closed++; } },
    localStorage: { getItem() { return null; }, setItem() {} },
    setInterval(callback) { retry = callback; },
    setTimeout: options.setTimeout || setTimeout, clearTimeout,
    chrome: { runtime: {
      sendMessage: async message => {
        sentMessages.push(message);
        if (message.type === "connectionRequest") return { ok: true, connection };
        if (message.type === "stateRequest") return options.snapshot ? options.snapshot() : { ok: true, state: { status: "idle" } };
        return typeof reply === "function" ? reply(message) : reply;
      },
      onMessage: { addListener(callback) { listener = callback; } }
    } }
  });
  return { elements, closed: () => closed, sentMessages,
    retry: () => retry(),
    connection: connection => listener({ channel: "pinboardshot.capture", type: "connection", connection }),
    state: state => listener({ channel: "pinboardshot.capture", type: "state", state }) };
}

test("an accepted manual capture keeps its side panel open", async () => {
  const view = popup({ ok: true });
  await new Promise(resolve => setImmediate(resolve));
  await view.elements.get("start").handlers.click();
  assert.equal(view.closed(), 0);
});

test("a disconnected app enables standalone capture and recovers the native mode", async () => {
  const view = popup({ ok: true }, { status: "disconnected" });
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(view.elements.get("start").disabled, false);
  assert.match(view.elements.get("connection").textContent, /独立模式/);
  assert.equal(view.elements.get("saveOptions").hidden, false);
  assert.equal(view.elements.get("start").textContent, "截图并保存 PNG");
  view.elements.get("saveAs").checked = true;
  await view.elements.get("start").handlers.click();
  assert.equal(view.sentMessages.find(message => message.type === "start").saveAs, true);
  view.connection({ status: "connected" });
  assert.equal(view.elements.get("start").disabled, false);
  assert.match(view.elements.get("connection").textContent, /已连接/);
  assert.equal(view.elements.get("saveOptions").hidden, true);
  view.retry();
  assert.equal(view.sentMessages.filter(message => message.type === "connectionRequest").length, 2);
});

test("standalone results and saving controls do not claim delivery to the App", async () => {
  const view = popup({ ok: true }, { status: "disconnected" });
  await new Promise(resolve => setImmediate(resolve));
  view.state({ status: "capturing", mode: "browser", progress: 42 });
  view.connection({ status: "connected" });
  assert.match(view.elements.get("description").textContent, /无需 App/);
  view.state({ status: "saving", mode: "browser", progress: 100 });
  assert.equal(view.elements.get("start").hidden, true);
  assert.equal(view.elements.get("pause").hidden, true);
  assert.equal(view.elements.get("stop").hidden, true);
  assert.equal(view.elements.get("cancel").hidden, false);
  assert.equal(view.elements.get("progressArea").hidden, false);
  for (const status of ["complete", "stopped"]) {
    view.state({ status, mode: "browser", progress: 100 });
    assert.match(view.elements.get("message").textContent, /PNG/);
    assert.doesNotMatch(view.elements.get("message").textContent, /发送到 PinboardShot/);
    assert.equal(view.elements.get("progressArea").hidden, true);
  }
  await view.elements.get("language").handlers.click();
  assert.match(view.elements.get("message").textContent, /saved as a PNG/);
});

test("a rejected start keeps the popup open and shows its error", async () => {
  const view = popup({ ok: false, error: "unsupported_page" });
  await new Promise(resolve => setImmediate(resolve));
  await view.elements.get("start").handlers.click();
  assert.equal(view.closed(), 0);
  assert.match(view.elements.get("message").textContent, /不支持截图/);
});

test("capture completeness failures have readable messages in the control panel", () => {
  const view = popup({ ok: true });
  view.state({ status: "error", error: "visible_resource_timeout" });
  assert.match(view.elements.get("message").textContent, /图片或字体.*未能及时加载/);
  view.state({ status: "error", error: "multiple_scroll_regions" });
  assert.match(view.elements.get("message").textContent, /多个主要滚动区域/);
});

test("popup exposes pause, resume, and stop controls for an active capture", async () => {
  const view = popup({ ok: true });
  await new Promise(resolve => setImmediate(resolve));
  view.state({ status: "capturing", progress: 42 });
  await view.elements.get("pause").handlers.click();
  view.state({ status: "paused", progress: 42 });
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
  assert.equal(view.elements.get("progressArea").hidden, true);
  assert.match(view.elements.get("message").textContent, /截取的部分已发送/);
});

test("every terminal state clears progress and keeps its own result message", () => {
  const view = popup({ ok: true });
  for (const status of ["cancelled", "stopped", "stopped_empty", "complete"]) {
    view.state({ status: "capturing", progress: 67 });
    view.state({ status, progress: status === "complete" ? 100 : 67 });
    assert.equal(view.elements.get("progressArea").hidden, true, status);
    assert.equal(view.elements.get("progressBar").style.width, "0%", status);
    assert.equal(view.elements.get("progressPercent").textContent, "", status);
    assert.equal(view.elements.get("progressText").textContent, "", status);
    assert.ok(view.elements.get("message").textContent, status);
    assert.equal(view.elements.get("captureCard").attributes["aria-busy"], "false");
    view.connection({ status: "connected" });
    assert.equal(view.elements.get("progressArea").hidden, true);
  }
  view.state({ status: "error", progress: 67, error: "viewport_changed" });
  assert.equal(view.elements.get("progressArea").hidden, true);
  assert.equal(view.elements.get("start").textContent, "重试截图");
});

test("stopping and cancelling retain progress until the task acknowledges completion", () => {
  const view = popup({ ok: true });
  for (const status of ["stopping", "cancelling"]) {
    view.state({ status, progress: 67 });
    assert.equal(view.elements.get("progressArea").hidden, false);
    assert.equal(view.elements.get("progressPercent").textContent, "67%");
    assert.equal(view.elements.get("start").hidden, true);
  }
});

test("a pending start gives immediate feedback and sends only one request", async () => {
  let resolveStart;
  const view = popup(() => new Promise(resolve => { resolveStart = resolve; }));
  await new Promise(resolve => setImmediate(resolve));
  const button = view.elements.get("start");
  const first = button.handlers.click();
  assert.equal(button.disabled, true);
  assert.equal(button.textContent, "正在开始…");
  await button.handlers.click();
  assert.equal(view.sentMessages.filter(m => m.type === "start").length, 1);
  resolveStart({ ok: false, error: "unsupported_page" });
  await first;
  assert.equal(button.disabled, false);
  assert.match(view.elements.get("message").textContent, /不支持截图/);
});

test("pending controls prevent repeated actions and report rejected replies without clearing progress", async () => {
  for (const [id, type] of [["pause", "togglePause"], ["stop", "stop"], ["cancel", "cancel"]]) {
    let resolveAction;
    const view = popup(() => new Promise(resolve => { resolveAction = resolve; }));
    await new Promise(resolve => setImmediate(resolve));
    view.state({ status: "capturing", progress: 42 });
    const action = view.elements.get(id).handlers.click();
    for (const control of ["pause", "stop", "cancel"]) assert.equal(view.elements.get(control).disabled, true);
    await view.elements.get(id).handlers.click();
    assert.equal(view.sentMessages.filter(m => m.type === type).length, 1);
    resolveAction({ ok: false });
    await action;
    assert.match(view.elements.get("message").textContent, /操作未完成/);
    assert.equal(view.elements.get("progressPercent").textContent, "42%");
    assert.equal(view.elements.get(id).disabled, false);
  }
});

test("a failed control transport is visible and can be retried", async () => {
  const view = popup(() => Promise.reject(new Error("disconnected")));
  await new Promise(resolve => setImmediate(resolve));
  view.state({ status: "paused", progress: 42 });
  await view.elements.get("pause").handlers.click();
  assert.match(view.elements.get("message").textContent, /操作未完成/);
  assert.equal(view.elements.get("pause").textContent, "继续截图");
  assert.equal(view.elements.get("pause").disabled, false);
  view.elements.get("language").handlers.click();
  assert.match(view.elements.get("message").textContent, /did not complete/);
});

test("a native acknowledgement keeps pause locked until the state transition arrives", async () => {
  const view = popup({ ok: true }, { status: "connected" }, {
    snapshot: () => ({ ok: true, state: { status: "capturing", progress: 42 } })
  });
  await new Promise(resolve => setImmediate(resolve));
  const action = view.elements.get("pause").handlers.click();
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(view.elements.get("pause").disabled, true);
  assert.equal(view.elements.get("pause").textContent, "正在暂停…");
  await view.elements.get("pause").handlers.click();
  assert.equal(view.sentMessages.filter(m => m.type === "togglePause").length, 1);
  view.state({ status: "paused", progress: 42 });
  await action;
  assert.equal(view.elements.get("pause").disabled, false);
  assert.equal(view.elements.get("pause").textContent, "继续截图");
});

test("an unconfirmed stop does not lock the UI indefinitely or clear current progress", async () => {
  let expire;
  const view = popup({ ok: true }, { status: "connected" }, {
    snapshot: () => ({ ok: true, state: { status: "capturing", progress: 42 } }),
    setTimeout(callback) { expire = callback; }
  });
  await new Promise(resolve => setImmediate(resolve));
  const action = view.elements.get("stop").handlers.click();
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(view.elements.get("stop").textContent, "正在保存…");
  expire();
  await action;
  assert.match(view.elements.get("message").textContent, /尚未确认/);
  assert.equal(view.elements.get("progressPercent").textContent, "42%");
  assert.equal(view.elements.get("stop").disabled, false);
});

test("a stale initial snapshot cannot resurrect progress after a terminal broadcast", async () => {
  let resolveSnapshot;
  const view = popup({ ok: true }, { status: "connected" }, {
    snapshot: () => new Promise(resolve => { resolveSnapshot = resolve; })
  });
  view.state({ status: "cancelled", progress: 42 });
  resolveSnapshot({ ok: true, state: { status: "capturing", progress: 42 } });
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(view.elements.get("progressArea").hidden, true);
  assert.match(view.elements.get("message").textContent, /已丢弃/);
  view.elements.get("language").handlers.click();
  assert.match(view.elements.get("message").textContent, /discarded/);
  assert.equal(view.sentMessages.filter(m => m.type === "stateRequest").length, 1);
});

test("reopening a panel after stop displays the saved result without old progress", async () => {
  const view = popup({ ok: true }, { status: "connected" }, {
    snapshot: () => ({ ok: true, state: { status: "stopped", progress: 42 } })
  });
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(view.elements.get("progressArea").hidden, true);
  assert.equal(view.elements.get("start").textContent, "再截一次");
  assert.match(view.elements.get("message").textContent, /截取的部分已发送/);
});

test("panel motion and symbols follow capture state rather than progress polling", () => {
  const view = popup({ ok: true });
  view.state({ status: "capturing", progress: 42 });
  assert.equal(view.elements.get("panel").attributes["data-state"], "capturing");
  assert.equal(view.elements.get("sceneBadge").hidden, true);
  view.state({ status: "paused", progress: 42 });
  assert.equal(view.elements.get("panel").attributes["data-state"], "paused");
  assert.equal(view.elements.get("pause").attributes["data-mode"], "resume");
  assert.equal(view.elements.get("sceneBadge").attributes["data-symbol"], "pause");
  view.state({ status: "stopped", progress: 42 });
  assert.equal(view.elements.get("sceneBadge").attributes["data-symbol"], "check");
  assert.equal(view.elements.get("resultTitle").textContent, "已保存截取部分");
  assert.equal(view.elements.get("progressArea").hidden, true);
  view.state({ status: "cancelled", progress: 42 });
  assert.equal(view.elements.get("sceneBadge").attributes["data-symbol"], "x");
});
