(() => {
  const CHANNEL = "pinboardshot.capture";
  const MAX_ELEMENTS = 30000;
  const RESTORE_KEY = "__pinboardShotCaptureState";
  const INSTALLED_KEY = "__pinboardShotCaptureInstalled";
  if (globalThis[INSTALLED_KEY]) return;

  function metrics() {
    const root = document.scrollingElement;
    return {
      scrollX: window.scrollX,
      scrollY: window.scrollY,
      viewportWidth: window.innerWidth,
      viewportHeight: window.innerHeight,
      documentHeight: Math.max(root?.scrollHeight || 0, document.documentElement.scrollHeight, document.body?.scrollHeight || 0),
      devicePixelRatio: window.devicePixelRatio || 1
    };
  }

  function bounded(promise, milliseconds) {
    return Promise.race([promise.catch(() => {}), new Promise(resolve => setTimeout(resolve, milliseconds))]);
  }

  const api = {
    prepare() {
      if (window[RESTORE_KEY]) throw new Error("capture_already_active");
      const root = document.scrollingElement;
      if (!root) throw new Error("scroll_root_unavailable");
      const scrollStyleElements = [document.documentElement, document.body].filter(Boolean);
      const state = {
        scrollX: window.scrollX,
        scrollY: window.scrollY,
        viewportWidth: window.innerWidth,
        viewportHeight: window.innerHeight,
        scrollStyles: scrollStyleElements.map(element => ({
          element,
          behavior: element.style.getPropertyValue("scroll-behavior"),
          behaviorPriority: element.style.getPropertyPriority("scroll-behavior"),
          snap: element.style.getPropertyValue("scroll-snap-type"),
          snapPriority: element.style.getPropertyPriority("scroll-snap-type")
        })),
        hidden: new Map(),
        restored: false
      };
      window[RESTORE_KEY] = state;
      for (const saved of state.scrollStyles) {
        saved.element.style.setProperty("scroll-behavior", "auto", "important");
        saved.element.style.setProperty("scroll-snap-type", "none", "important");
      }
      window.addEventListener("keydown", onKeyDown, true);
      return { ...metrics(), originalScrollY: state.scrollY };
    },

    async goTo(targetY, hideFixed) {
      const state = window[RESTORE_KEY];
      if (!state) throw new Error("capture_not_active");
      if (!Number.isFinite(targetY) || targetY < 0) throw new Error("invalid_scroll_target");
      if (hideFixed) hideFixedElements(state);
      const before = metrics();
      const maxY = Math.max(0, before.documentHeight - before.viewportHeight);
      window.scrollTo(0, Math.min(targetY, maxY));
      await settleScroll();
      await waitVisibleResources();
      const after = metrics();
      if (after.viewportWidth !== state.viewportWidth || after.viewportHeight !== state.viewportHeight) {
        throw new Error("viewport_changed");
      }
      if (after.scrollX !== 0) throw new Error("horizontal_scroll_unsupported");
      return after;
    },

    restore() {
      const state = window[RESTORE_KEY];
      if (!state || state.restored) return { restored: true };
      state.restored = true;
      window.removeEventListener("keydown", onKeyDown, true);
      for (const [element, saved] of state.hidden) {
        if (!element.isConnected) continue;
        if (saved.value) element.style.setProperty("visibility", saved.value, saved.priority);
        else element.style.removeProperty("visibility");
      }
      // Restore scroll while smooth behavior and snapping are still disabled.
      window.scrollTo(state.scrollX, state.scrollY);
      for (const saved of state.scrollStyles) {
        if (!saved.element.isConnected) continue;
        if (saved.behavior) saved.element.style.setProperty("scroll-behavior", saved.behavior, saved.behaviorPriority);
        else saved.element.style.removeProperty("scroll-behavior");
        if (saved.snap) saved.element.style.setProperty("scroll-snap-type", saved.snap, saved.snapPriority);
        else saved.element.style.removeProperty("scroll-snap-type");
      }
      delete window[RESTORE_KEY];
      return { restored: true };
    },

    getMetrics: metrics
  };

  function hideFixedElements(state) {
    let visited = 0;
    for (const element of document.querySelectorAll("body *")) {
      if (++visited > MAX_ELEMENTS) break;
      if (state.hidden.has(element)) continue;
      const position = getComputedStyle(element).position;
      if (position !== "fixed" && position !== "sticky") continue;
      state.hidden.set(element, {
        value: element.style.getPropertyValue("visibility"),
        priority: element.style.getPropertyPriority("visibility")
      });
      element.style.setProperty("visibility", "hidden", "important");
    }
  }

  async function settleScroll() {
    // Chrome can suspend animation frames for an occluded page. Keep scroll
    // replies bounded so the worker can acknowledge Pause and finish Stop.
    await bounded(new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))), 250);
    let previous = window.scrollY;
    let stable = 0;
    const deadline = Date.now() + 2200;
    while (Date.now() < deadline) {
      await new Promise(resolve => setTimeout(resolve, 50));
      const current = window.scrollY;
      if (Math.abs(current - previous) < 0.5) stable++;
      else stable = 0;
      if (stable >= 2) return;
      previous = current;
    }
    throw new Error("scroll_did_not_settle");
  }

  async function waitVisibleResources() {
    const fontWait = document.fonts?.ready || Promise.resolve();
    await bounded(fontWait, 900);
    const pending = [];
    for (const image of document.images) {
      const rect = image.getBoundingClientRect();
      if (rect.bottom < -100 || rect.top > window.innerHeight + 100) continue;
      if (image.complete && image.naturalWidth > 0) continue;
      if (typeof image.decode === "function") pending.push(image.decode());
    }
    await bounded(Promise.all(pending), 1200);
    // Resource readiness must not reintroduce an unbounded frame wait.
    await bounded(new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))), 250);
  }

  function onKeyDown(event) {
    if (event.key !== "Escape" || !window[RESTORE_KEY]) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    chrome.runtime.sendMessage({ channel: CHANNEL, type: "cancelByUser" }).catch(() => {});
  }

  chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
    if (sender.id !== chrome.runtime.id || message?.channel !== CHANNEL || typeof message.type !== "string") return false;
    if (message.type === "prepare") {
      try { sendResponse({ ok: true, metrics: api.prepare() }); }
      catch (error) { sendResponse({ ok: false, error: error.message || "prepare_failed" }); }
      return false;
    }
    if (message.type === "goTo") {
      api.goTo(message.targetY, message.hideFixed === true)
        .then(value => sendResponse({ ok: true, metrics: value }))
        .catch(error => sendResponse({ ok: false, error: error.message || "scroll_failed" }));
      return true;
    }
    if (message.type === "restore") {
      try { sendResponse({ ok: true, ...api.restore() }); }
      catch (error) { sendResponse({ ok: false, error: error.message || "restore_failed" }); }
      return false;
    }
    if (message.type === "metrics") {
      try { sendResponse({ ok: true, metrics: api.getMetrics() }); }
      catch (error) { sendResponse({ ok: false, error: "metrics_failed" }); }
      return false;
    }
    return false;
  });

  Object.defineProperty(globalThis, "__pinboardShotCapture", { value: api, configurable: true });
  Object.defineProperty(globalThis, INSTALLED_KEY, { value: true, configurable: false });
})();
