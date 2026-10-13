(() => {
  const CHANNEL = "pinboardshot.capture";
  const MAX_ELEMENTS = 30000;
  const RESTORE_KEY = "__pinboardShotCaptureState";
  const INSTALLED_KEY = "__pinboardShotCaptureInstalled";
  if (globalThis[INSTALLED_KEY]) return;

  function metrics() {
    const state = window[RESTORE_KEY];
    if (state?.container) {
      const rect = containerRect(state.container);
      return {
        scrollX: state.container.scrollLeft, scrollY: state.container.scrollTop,
        viewportWidth: rect.width, viewportHeight: rect.height,
        documentHeight: state.container.scrollHeight, devicePixelRatio: window.devicePixelRatio || 1,
        browserViewportWidth: window.innerWidth, browserViewportHeight: window.innerHeight,
        captureRect: rect, requiredOverlap: state.requiredOverlap
      };
    }
    const root = document.scrollingElement;
    return {
      scrollX: window.scrollX,
      scrollY: window.scrollY,
      viewportWidth: window.innerWidth,
      viewportHeight: window.innerHeight,
      documentHeight: Math.max(root?.scrollHeight || 0, document.documentElement.scrollHeight, document.body?.scrollHeight || 0),
      devicePixelRatio: window.devicePixelRatio || 1,
      requiredOverlap: state?.requiredOverlap || 0.15
    };
  }

  function containerRect(element) {
    if (!element.isConnected) throw new Error("scroll_container_changed");
    const rect = element.getBoundingClientRect();
    const result = { x: rect.left + element.clientLeft, y: rect.top + element.clientTop,
      width: element.clientWidth, height: element.clientHeight };
    // Cropping an occluded or transformed pane would silently discard pixels.
    if (Math.abs(rect.width - element.offsetWidth) > 1 || Math.abs(rect.height - element.offsetHeight) > 1 ||
        result.x < 0 || result.y < 0 || result.x + result.width > window.innerWidth + 0.5 ||
        result.y + result.height > window.innerHeight + 0.5) throw new Error("scroll_container_not_visible");
    for (const [x, y] of [[result.x + 1, result.y + 1], [result.x + result.width - 1, result.y + 1],
      [result.x + 1, result.y + result.height - 1], [result.x + result.width - 1, result.y + result.height - 1],
      [result.x + result.width / 2, result.y + result.height / 2]]) {
      const visible = document.elementFromPoint(x, y);
      if (!visible || (visible !== element && !element.contains(visible))) throw new Error("scroll_container_not_visible");
    }
    return result;
  }

  function scrollingContainer(elements, root) {
    const candidates = [];
    for (const element of elements) {
      if (element === root || element === document.body || element.clientHeight < 180 || element.clientWidth < 200 ||
          element.scrollHeight <= element.clientHeight + 2) continue;
      const style = getComputedStyle(element);
      if (!/^(auto|scroll|overlay)$/.test(style.overflowY) || style.visibility === "hidden") continue;
      const rect = element.getBoundingClientRect();
      const area = element.clientWidth * element.clientHeight;
      if (area < window.innerWidth * window.innerHeight * 0.25 || rect.bottom <= 0 || rect.top >= window.innerHeight) continue;
      candidates.push({ element, area });
    }
    if (!candidates.length) return null;
    // A page with multiple substantial panes needs an explicit selection; never
    // label its outer shell as a complete capture of the hidden pane contents.
    if (root.scrollHeight > window.innerHeight + 2) throw new Error("multiple_scroll_regions");
    if (candidates.length > 1) throw new Error("multiple_scroll_regions");
    containerRect(candidates[0].element);
    return candidates[0].element;
  }

  function saveStyle(state, element, name, value) {
    state.changedStyles.push({ element, name, value: element.style.getPropertyValue(name),
      priority: element.style.getPropertyPriority(name) });
    element.style.setProperty(name, value, "important");
  }

  function bounded(promise, milliseconds) {
    return Promise.race([promise.catch(() => {}), new Promise(resolve => setTimeout(resolve, milliseconds))]);
  }

  const api = {
    prepare() {
      if (window[RESTORE_KEY]) throw new Error("capture_already_active");
      const root = document.scrollingElement;
      if (!root) throw new Error("scroll_root_unavailable");
      const elements = Array.from(document.querySelectorAll("body *"));
      if (elements.length > MAX_ELEMENTS) throw new Error("page_structure_too_large");
      const container = scrollingContainer(elements, root);
      const scrollStyleElements = [document.documentElement, document.body, container].filter(Boolean);
      const state = {
        container,
        containerScrollX: container?.scrollLeft,
        containerScrollY: container?.scrollTop,
        captureRect: container ? containerRect(container) : null,
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
        changedStyles: [],
        requiredOverlap: 0.15,
        restored: false
      };
      window[RESTORE_KEY] = state;
      for (const saved of state.scrollStyles) {
        saved.element.style.setProperty("scroll-behavior", "auto", "important");
        saved.element.style.setProperty("scroll-snap-type", "none", "important");
      }
      for (const element of elements) {
        if (container && (element === container || !container.contains(element))) continue;
        if (getComputedStyle(element).position !== "sticky") continue;
        // Sticky headings belong to document flow, including headings below the
        // first viewport. Unpin them rather than hiding content never captured.
        saveStyle(state, element, "position", "relative");
        for (const name of ["top", "right", "bottom", "left"]) saveStyle(state, element, name, "auto");
      }
      const capture = state.captureRect || { x: 0, y: 0, width: window.innerWidth, height: window.innerHeight };
      for (const element of elements) {
        if (container && (element === container || element.contains(container))) continue;
        if (getComputedStyle(element).position !== "fixed") continue;
        const rect = element.getBoundingClientRect();
        if (rect.right <= capture.x || rect.left >= capture.x + capture.width || rect.top >= capture.y + capture.height ||
            rect.bottom < capture.y + capture.height - 1) continue;
        const obscured = capture.y + capture.height - Math.max(capture.y, rect.top);
        state.requiredOverlap = Math.max(state.requiredOverlap, obscured / capture.height + 0.01);
      }
      if (state.requiredOverlap >= 0.9) throw new Error("fixed_overlay_too_large");
      window.addEventListener("keydown", onKeyDown, true);
      return { ...metrics(), originalScrollY: container ? state.containerScrollY : state.scrollY };
    },

    async goTo(targetY, hideFixed) {
      const state = window[RESTORE_KEY];
      if (!state) throw new Error("capture_not_active");
      if (!Number.isFinite(targetY) || targetY < 0) throw new Error("invalid_scroll_target");
      if (hideFixed) hideFixedElements(state);
      const before = metrics();
      const maxY = Math.max(0, before.documentHeight - before.viewportHeight);
      if (state.container) state.container.scrollTo(0, Math.min(targetY, maxY));
      else window.scrollTo(0, Math.min(targetY, maxY));
      await settleScroll();
      await waitVisibleResources();
      const after = metrics();
      if (window.innerWidth !== state.viewportWidth || window.innerHeight !== state.viewportHeight ||
          (state.captureRect && ["x", "y", "width", "height"].some(key => Math.abs(after.captureRect[key] - state.captureRect[key]) > 0.5))) {
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
      for (const saved of state.changedStyles.reverse()) {
        if (!saved.element.isConnected) continue;
        if (saved.value) saved.element.style.setProperty(saved.name, saved.value, saved.priority);
        else saved.element.style.removeProperty(saved.name);
      }
      // Restore scroll while smooth behavior and snapping are still disabled.
      if (state.container?.isConnected) state.container.scrollTo(state.containerScrollX, state.containerScrollY);
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
      if (state.container && (element === state.container || element.contains(state.container))) continue;
      const position = getComputedStyle(element).position;
      if (position !== "fixed") continue;
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
    const scrollY = () => window[RESTORE_KEY]?.container?.scrollTop ?? window.scrollY;
    let previous = scrollY();
    let stable = 0;
    const deadline = Date.now() + 2200;
    while (Date.now() < deadline) {
      await new Promise(resolve => setTimeout(resolve, 50));
      const current = scrollY();
      if (Math.abs(current - previous) < 0.5) stable++;
      else stable = 0;
      if (stable >= 2) return;
      previous = current;
    }
    throw new Error("scroll_did_not_settle");
  }

  async function waitVisibleResources() {
    async function required(promise, milliseconds) {
      let timer;
      try {
        await Promise.race([promise.catch(() => { throw new Error("visible_resource_failed"); }),
          new Promise((_, reject) => { timer = setTimeout(() => reject(new Error("visible_resource_timeout")), milliseconds); })]);
      } finally { clearTimeout(timer); }
    }
    const fontWait = document.fonts?.ready || Promise.resolve();
    await required(fontWait, 2000);
    const pending = [];
    const state = window[RESTORE_KEY];
    const capture = state?.container ? containerRect(state.container) : { x: 0, y: 0, width: window.innerWidth, height: window.innerHeight };
    for (const image of document.images) {
      if (state?.container && !state.container.contains(image)) continue;
      const rect = image.getBoundingClientRect();
      if (rect.width <= 0 || rect.height <= 0 || rect.bottom <= capture.y || rect.top >= capture.y + capture.height ||
          rect.right <= capture.x || rect.left >= capture.x + capture.width || getComputedStyle(image).visibility === "hidden") continue;
      if (image.complete) {
        if (image.currentSrc && image.naturalWidth === 0) throw new Error("visible_resource_failed");
        continue;
      }
      if (typeof image.decode === "function") pending.push(image.decode());
    }
    // A timeout is incomplete content, not a successful blank placeholder tile.
    await required(Promise.all(pending), 5000);
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
