import { captureBudget, MAX_CAPTURE_MS, MAX_TILES, MIN_CAPTURE_INTERVAL_MS, nextTarget, progressPercent, validateMetrics } from "./lib/planner.mjs";
import { splitBase64 } from "./lib/native-protocol.mjs";
import { NativeCaptureClient } from "./lib/native-client.mjs";

const CHANNEL = "pinboardshot.capture";
const captureState = { status: "idle", progress: 0, error: null, tabId: null };
let activeCapture = null;
const CONTROL_POLL_INTERVAL_MS = 250;
const CHROME_CAPTURE_TIMEOUT_MS = 30000;

function publish() {
  chrome.runtime.sendMessage({ channel: CHANNEL, type: "state", state: { ...captureState } }).catch(() => {});
}

function setState(status, progress = captureState.progress, error = null) {
  Object.assign(captureState, { status, progress, error });
  publish();
}

function errorCode(error) {
  if (error?.captureSaved === true && error?.nativeCode === "app_open_failed") return "capture_saved_app_open_failed";
  const raw = String(error?.message || "capture_failed");
  if (/native messaging host|native host|native_disconnected|could not establish connection/i.test(raw)) return "native_disconnected";
  const code = raw.replace(/[^a-zA-Z0-9_-]/g, "_").slice(0, 80);
  return code || "capture_failed";
}

async function sendToContent(tabId, message) {
  const reply = await boundedChromeCall(
    () => chrome.tabs.sendMessage(tabId, { channel: CHANNEL, ...message }),
    "page_response_timeout", message.type !== "restore");
  if (!reply?.ok) throw new Error(reply?.error || "page_capture_failed");
  return reply;
}

async function boundedChromeCall(start, timeoutCode, cancelable = true) {
  const run = activeCapture;
  if (cancelable && run?.cancelled) throw new Error("cancelled");
  let timer;
  let cancelWaiter;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error(timeoutCode)), CHROME_CAPTURE_TIMEOUT_MS);
  });
  const pending = [timeout];
  if (cancelable && run) {
    pending.push(new Promise((_, reject) => {
      cancelWaiter = () => reject(new Error("cancelled"));
      run.cancelWaiters.add(cancelWaiter);
    }));
  }
  try {
    return await Promise.race([start(), ...pending]);
  } finally {
    clearTimeout(timer);
    if (cancelWaiter) run.cancelWaiters.delete(cancelWaiter);
  }
}

async function activeTabMatches(tabId, windowId) {
  const focused = await boundedChromeCall(() => chrome.windows.getLastFocused({ populate: true }), "tab_query_timeout");
  const activeTab = focused.tabs?.find(tab => tab.active);
  // captureVisibleTab targets this Chrome window, even while a popup or another app has OS focus.
  return focused.id === windowId && activeTab?.id === tabId && activeTab.windowId === windowId;
}

async function waitForTab(tabId, windowId) {
  if (activeCapture.cancelled) throw new Error("cancelled");
  if (!await activeTabMatches(tabId, windowId)) throw new Error("active_tab_changed");
}

async function captureVisible(tabId, windowId) {
  await waitForTab(tabId, windowId);
  // A pending Chrome API must not trap Cancel or hold the page and native session indefinitely.
  const dataUrl = await boundedChromeCall(
    () => chrome.tabs.captureVisibleTab(windowId, { format: "png" }), "screenshot_timeout");
  await waitForTab(tabId, windowId);
  const comma = dataUrl.indexOf(",");
  if (comma < 0 || !dataUrl.startsWith("data:image/png;base64,")) throw new Error("invalid_screenshot");
  return dataUrl.slice(comma + 1);
}

function sameCaptureGeometry(first, second) {
  const sameViewport = first.viewportWidth === second.viewportWidth && first.viewportHeight === second.viewportHeight &&
    first.devicePixelRatio === second.devicePixelRatio;
  const sameVerticalPixel = Math.round(first.scrollY * first.devicePixelRatio) === Math.round(second.scrollY * second.devicePixelRatio);
  const sameHorizontalPixel = Math.round(first.scrollX * first.devicePixelRatio) === Math.round(second.scrollX * second.devicePixelRatio);
  return sameViewport && sameVerticalPixel && sameHorizontalPixel;
}

async function waitCaptureRate() {
  const remaining = MIN_CAPTURE_INTERVAL_MS - (Date.now() - activeCapture.lastCaptureAt);
  if (remaining > 0) await new Promise(resolve => setTimeout(resolve, remaining));
  if (activeCapture.cancelled) throw new Error("cancelled");
}

async function waitForResume(run) {
  if (run.cancelled) throw new Error("cancelled");
  if (run.stopRequested) return "stopped";
  if (!run.paused) return false;
  // A tile already being captured/transmitted finishes before acknowledging pause.
  // This keeps the native image valid and prevents a second scroll while paused.
  setState("paused");
  await new Promise(resolve => { run.resume = resolve; });
  run.resume = null;
  if (run.cancelled) throw new Error("cancelled");
  if (run.stopRequested) return "stopped";
  return "resumed";
}

function waitForControlRevision(run, revision) {
  if (run.controlRevision > revision || run.controlError || run.controlPollingStopped) return Promise.resolve();
  return new Promise(resolve => run.controlWaiters.push({ revision, resolve }));
}

function publishControlRevision(run) {
  run.controlRevision++;
  const ready = run.controlWaiters.filter(waiter => run.controlRevision > waiter.revision);
  run.controlWaiters = run.controlWaiters.filter(waiter => run.controlRevision <= waiter.revision);
  for (const waiter of ready) waiter.resolve();
}

function applyNativeControl(run, response) {
  if (typeof response.paused !== "boolean" || typeof response.stopped !== "boolean") {
    throw new Error("native_protocol_error");
  }
  run.remotePaused = response.paused;
  run.desiredPaused = response.paused;
  if (run.paused !== response.paused) {
    setPaused(run, response.paused);
  }
  run.remoteStopped = response.stopped;
  if (response.stopped) observeStopRequest(run);
}

async function pollNativeControl(run, client, captureId) {
  try {
    while (!run.controlPollingStopped) {
      await new Promise(resolve => setTimeout(resolve, CONTROL_POLL_INTERVAL_MS));
      if (run.controlPollingStopped) break;
      const response = await client.request("control", {
        captureId,
        status: captureState.status,
        progress: captureState.progress
      });
      applyNativeControl(run, response);
      publishControlRevision(run);
    }
  } catch (error) {
    if (!run.controlPollingStopped) {
      run.controlError = error;
      run.cancelled = true;
      run.resume?.();
      publishControlRevision(run);
    }
  }
}

async function stopNativeControlPolling(run) {
  run.controlPollingStopped = true;
  for (const waiter of run.controlWaiters) waiter.resolve();
  run.controlWaiters = [];
  await run.controlTask?.catch(() => {});
}

function setPaused(run, paused) {
  if (run.cancelled || run.stopRequested || run.paused === paused) return;
  if (paused) {
    run.paused = true;
    run.pausedAt = Date.now();
    setState("pausing");
    return;
  }
  // User pause time must not consume the five-minute capture budget.
  if (run.pausedAt) run.startedAt += Date.now() - run.pausedAt;
  run.pausedAt = 0;
  run.paused = false;
  run.resume?.();
  setState("capturing");
}

async function togglePause() {
  const run = activeCapture;
  if (!run || run.cancelled || run.stopRequested || !run.client || !run.captureId) return false;
  const paused = !(run.desiredPaused ?? run.remotePaused ?? run.paused);
  run.desiredPaused = paused;
  try {
    await run.client.request("setControl", { captureId: run.captureId, paused, stopped: run.remoteStopped === true });
    return true;
  } catch (error) {
    run.desiredPaused = run.remotePaused;
    throw error;
  }
}

async function requestStop() {
  const run = activeCapture;
  if (!run || run.cancelled || run.stopRequested || !run.client || !run.captureId) return false;
  try {
    await run.client.request("setControl", {
      captureId: run.captureId, paused: run.remotePaused === true, stopped: true
    });
    return true;
  } catch (error) {
    throw error;
  }
}

function observeStopRequest(run) {
  if (!run || run.cancelled || run.stopRequested) return false;
  run.stopRequested = true;
  run.paused = false;
  run.resume?.();
  setState("stopping", captureState.progress);
  return true;
}

async function finishAtStopBoundary(client, captureId, run, tileCount, coveredHeight) {
  await stopNativeControlPolling(run);
  if (tileCount > 0) {
    await client.request("finish", {
      captureId,
      capturedHeight: Math.min(coveredHeight, run.lastTileDocumentHeight)
    });
  } else {
    await client.request("cancel", { captureId });
  }
  run.completed = true;
  setState(tileCount > 0 ? "stopped" : "stopped_empty", captureState.progress);
}

function cancelCapture() {
  const run = activeCapture;
  if (!run || run.cancelled || run.stopRequested) return false;
  run.cancelled = true;
  for (const wake of run.cancelWaiters) wake();
  run.resume?.();
  setState("cancelling", captureState.progress);
  return true;
}

async function waitForQuietBottom(tabId, windowId, initialMetrics) {
  let latest = initialMetrics;
  let stableChecks = 0;
  for (let check = 0; check < 5 && stableChecks < 2; check++) {
    await new Promise(resolve => setTimeout(resolve, 450));
    await waitForTab(tabId, windowId);
    const current = await sendToContent(tabId, { type: "metrics" }).then(reply => reply.metrics);
    validateMetrics(current);
    if (Math.abs(current.documentHeight - latest.documentHeight) < 0.5) stableChecks++;
    else stableChecks = 0;
    latest = current;
  }
  return latest;
}

async function transmitTile(client, captureId, index, metrics, pngBase64) {
  const chunks = splitBase64(pngBase64, client.maxChunkChars);
  await client.request("tileBegin", {
    captureId, index, scrollY: metrics.scrollY,
    viewportWidth: metrics.viewportWidth, viewportHeight: metrics.viewportHeight,
    documentHeight: metrics.documentHeight, base64Length: pngBase64.length
  });
  for (let sequence = 0; sequence < chunks.length; sequence++) {
    if (activeCapture.cancelled) throw new Error("cancelled");
    await client.request("tileChunk", { captureId, index, sequence, data: chunks[sequence] });
  }
  await client.request("tileEnd", { captureId, index });
}

async function runCapture(tab) {
  if (activeCapture) throw new Error("capture_already_active");
  if (!tab?.id || !Number.isInteger(tab.windowId) || !/^https?:/i.test(tab.url || "")) throw new Error("unsupported_page");
  const run = {
    cancelled: false, stopRequested: false, paused: false, pausedAt: 0, resume: null,
    startedAt: Date.now(), lastCaptureAt: 0, tabId: tab.id, windowId: tab.windowId,
    controlRevision: 0, controlWaiters: [], controlPollingStopped: false,
    remotePaused: null, desiredPaused: null, remoteStopped: null,
    controlTask: null, controlError: null, client: null, captureId: null,
    lastTileDocumentHeight: 0, cancelWaiters: new Set()
  };
  activeCapture = run;
  Object.assign(captureState, { status: "preparing", progress: 0, error: null, tabId: tab.id });
  publish();

  const client = new NativeCaptureClient(chrome);
  let captureId = null;
  let prepared = false;
  let completed = false;
  let coveredHeight = 0;
  let previousTileBottomPixels = 0;
  let tileCount = 0;
  let previousViewportWidth = null;
  let previousViewportHeight = null;
  let expectedTarget = 0;
  try {
    await client.connect();
    const begun = await client.request("begin");
    if (typeof begun.captureId !== "string" || !begun.captureId) throw new Error("native_protocol_error");
    captureId = begun.captureId;
    run.client = client;
    run.captureId = captureId;
    run.controlTask = pollNativeControl(run, client, captureId);
    await waitForTab(tab.id, tab.windowId);
    await chrome.scripting.executeScript({ target: { tabId: tab.id }, files: ["capture.js"] });
    prepared = true;
    const initial = (await sendToContent(tab.id, { type: "prepare" })).metrics;
    validateMetrics(initial);
    previousViewportWidth = initial.viewportWidth;
    previousViewportHeight = initial.viewportHeight;
    captureBudget(initial, 0);
    await waitForControlRevision(run, 0);
    if (run.controlError) throw run.controlError;
    if (await waitForResume(run) === "stopped") {
      await finishAtStopBoundary(client, captureId, run, tileCount, coveredHeight);
      completed = true;
      return;
    }
    await waitForTab(tab.id, tab.windowId);
    let metrics = await sendToContent(tab.id, { type: "goTo", targetY: 0, hideFixed: false }).then(reply => reply.metrics);

    setState("capturing", 0);
    while (true) {
      if (run.stopRequested) {
        await finishAtStopBoundary(client, captureId, run, tileCount, coveredHeight);
        completed = true;
        break;
      }
      if (await waitForResume(run) === "resumed") {
        await waitForTab(tab.id, tab.windowId);
        // Return to the saved tile position if the page was moved during pause.
        metrics = (await sendToContent(tab.id, { type: "goTo", targetY: expectedTarget, hideFixed: tileCount > 0 })).metrics;
      }
      if (run.cancelled) throw new Error("cancelled");
      if (Date.now() - run.startedAt > MAX_CAPTURE_MS) throw new Error("time_budget_exceeded");
      if (tileCount >= MAX_TILES) throw new Error("tile_budget_exceeded");
      validateMetrics(metrics);
      if (metrics.viewportWidth !== previousViewportWidth || metrics.viewportHeight !== previousViewportHeight) throw new Error("viewport_changed");
      captureBudget(metrics, tileCount + 1);
      if (Math.abs(metrics.scrollY - expectedTarget) > 2 && !(expectedTarget === 0 && metrics.scrollY < 2)) {
        throw new Error("scroll_position_unexpected");
      }
      const tileTopPixels = Math.round(metrics.scrollY * metrics.devicePixelRatio);
      if (tileCount > 0 && tileTopPixels > previousTileBottomPixels) throw new Error("gap_detected");

      await waitCaptureRate();
      const beforeTileControlRevision = run.controlRevision;
      await waitForControlRevision(run, beforeTileControlRevision);
      if (run.controlError) throw run.controlError;
      const preTileControl = await waitForResume(run);
      if (preTileControl === "stopped") {
        await finishAtStopBoundary(client, captureId, run, tileCount, coveredHeight);
        completed = true;
        break;
      }
      if (preTileControl === "resumed") {
        await waitForTab(tab.id, tab.windowId);
        metrics = (await sendToContent(tab.id, { type: "goTo", targetY: expectedTarget, hideFixed: tileCount > 0 })).metrics;
      }
      if (await waitForResume(run) === "resumed") {
        await waitForTab(tab.id, tab.windowId);
        metrics = (await sendToContent(tab.id, { type: "goTo", targetY: expectedTarget, hideFixed: tileCount > 0 })).metrics;
      }
      await waitForTab(tab.id, tab.windowId);
      const beforeCapture = await sendToContent(tab.id, { type: "metrics" }).then(reply => reply.metrics);
      validateMetrics(beforeCapture);
      if (!sameCaptureGeometry(metrics, beforeCapture)) throw new Error("capture_position_changed");
      if (beforeCapture.viewportWidth !== previousViewportWidth || beforeCapture.viewportHeight !== previousViewportHeight ||
          beforeCapture.devicePixelRatio !== metrics.devicePixelRatio) throw new Error("viewport_changed");
      captureBudget(beforeCapture, tileCount + 1);
      const png = await captureVisible(tab.id, tab.windowId);
      const afterCapture = await sendToContent(tab.id, { type: "metrics" }).then(reply => reply.metrics);
      validateMetrics(afterCapture);
      if (!sameCaptureGeometry(beforeCapture, afterCapture)) throw new Error("capture_position_changed");
      if (afterCapture.viewportWidth !== previousViewportWidth || afterCapture.viewportHeight !== previousViewportHeight ||
          afterCapture.devicePixelRatio !== beforeCapture.devicePixelRatio) throw new Error("viewport_changed");
      captureBudget(afterCapture, tileCount + 1);
      run.lastCaptureAt = Date.now();
      metrics = { ...beforeCapture, documentHeight: afterCapture.documentHeight };
      await transmitTile(client, captureId, tileCount, metrics, png);
      run.lastTileDocumentHeight = metrics.documentHeight;
      tileCount++;
      previousTileBottomPixels = Math.max(previousTileBottomPixels,
        tileTopPixels + Math.round(metrics.viewportHeight * metrics.devicePixelRatio));
      coveredHeight = previousTileBottomPixels / metrics.devicePixelRatio;
      const controlRevisionAtBoundary = run.controlRevision;
      await waitForControlRevision(run, controlRevisionAtBoundary);
      if (run.controlError) throw run.controlError;
      const boundaryControl = await waitForResume(run);
      if (boundaryControl === "stopped") {
        await finishAtStopBoundary(client, captureId, run, tileCount, coveredHeight);
        completed = true;
        break;
      }
      if (Date.now() - run.startedAt > MAX_CAPTURE_MS) throw new Error("time_budget_exceeded");
      const percent = progressPercent(metrics.scrollY, metrics.viewportHeight, metrics.documentHeight);
      setState("capturing", percent);

      const live = await sendToContent(tab.id, { type: "metrics" }).then(reply => reply.metrics);
      validateMetrics(live);
      if (live.viewportWidth !== previousViewportWidth || live.viewportHeight !== previousViewportHeight) throw new Error("viewport_changed");
      captureBudget(live, tileCount);
      const target = nextTarget(metrics.scrollY, live.documentHeight, live.viewportHeight);
      if (target === null) {
        const latest = await waitForQuietBottom(tab.id, tab.windowId, live);
        if (await waitForResume(run) === "stopped") {
          await finishAtStopBoundary(client, captureId, run, tileCount, coveredHeight);
          completed = true;
          break;
        }
        if (latest.documentHeight > live.documentHeight + 0.5 && metrics.scrollY < latest.documentHeight - latest.viewportHeight - 0.5) {
          expectedTarget = nextTarget(metrics.scrollY, latest.documentHeight, latest.viewportHeight);
          await waitForTab(tab.id, tab.windowId);
          metrics = await sendToContent(tab.id, { type: "goTo", targetY: expectedTarget, hideFixed: true }).then(reply => reply.metrics);
          continue;
        }
        const actualCovered = Math.min(latest.documentHeight, coveredHeight);
        if (actualCovered + 0.5 < latest.documentHeight) throw new Error("incomplete_coverage");
        await stopNativeControlPolling(run);
        await client.request("finish", { captureId, capturedHeight: actualCovered });
        completed = true;
        setState("complete", 100);
        break;
      }
      expectedTarget = target;
      if (await waitForResume(run) === "stopped") {
        await finishAtStopBoundary(client, captureId, run, tileCount, coveredHeight);
        completed = true;
        break;
      }
      await waitForTab(tab.id, tab.windowId);
      metrics = await sendToContent(tab.id, { type: "goTo", targetY: target, hideFixed: true }).then(reply => reply.metrics);
      if (metrics.scrollY <= live.scrollY + 0.5 && target > live.scrollY + 0.5) throw new Error("scroll_stalled");
    }
  } catch (error) {
    const code = errorCode(run.controlError || error);
    if (error?.captureSaved === true) completed = true;
    if (captureId && !completed) {
      await stopNativeControlPolling(run);
      try { await client.request("cancel", { captureId }); } catch {}
    }
    setState(code === "cancelled" ? "cancelled" : "error", captureState.progress, code);
  } finally {
    await stopNativeControlPolling(run);
    client.disconnect();
    await run.controlTask?.catch(() => {});
    if (prepared) {
      try { await sendToContent(tab.id, { type: "restore" }); } catch {}
    }
    if (activeCapture === run) activeCapture = null;
  }
}

chrome.action.onClicked.addListener(tab => {
  // Only a real toolbar click opens persistent controls. The App's command
  // below deliberately starts capture without opening a second control panel.
  chrome.sidePanel.open({ windowId: tab.windowId }).catch(error => setState("error", 0, errorCode(error)));
});
chrome.commands.onCommand.addListener(async command => {
  if (command !== "start-long-screenshot" || activeCapture) return;
  const [tab] = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
  void runCapture(tab).catch(error => setState("error", captureState.progress, errorCode(error)));
});

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (sender.id !== chrome.runtime.id || message?.channel !== CHANNEL) return false;
  const popupSender = !sender.tab && sender.url === chrome.runtime.getURL("popup.html");
  if (message.type === "stateRequest") {
    if (!popupSender) return false;
    sendResponse({ ok: true, state: { ...captureState } });
    return false;
  }
  if (message.type === "start") {
    if (!popupSender) return false;
    if (activeCapture) {
      sendResponse({ ok: false, error: "capture_already_active" });
      return false;
    }
    chrome.tabs.query({ active: true, lastFocusedWindow: true }).then(([tab]) => {
      // The window-wide side panel persists across tabs, but activeTab access does not.
      if (!tab?.url) {
        sendResponse({ ok: false, error: "invoke_on_current_tab" });
        return;
      }
      void runCapture(tab).catch(error => setState("error", captureState.progress, errorCode(error)));
      sendResponse({ ok: true });
    }).catch(error => sendResponse({ ok: false, error: errorCode(error) }));
    return true;
  }
  if (message.type === "cancel") {
    if (!popupSender) return false;
    sendResponse({ ok: cancelCapture() });
    return false;
  }
  if (message.type === "stop") {
    if (!popupSender) return false;
    requestStop().then(ok => sendResponse({ ok })).catch(error => sendResponse({ ok: false, error: errorCode(error) }));
    return true;
  }
  if (message.type === "togglePause") {
    if (!popupSender) return false;
    togglePause().then(ok => sendResponse({ ok })).catch(error => sendResponse({ ok: false, error: errorCode(error) }));
    return true;
  }
  if (message.type === "cancelByUser") {
    if (!sender.tab || sender.tab.id !== activeCapture?.tabId || sender.frameId !== 0) return false;
    sendResponse({ ok: cancelCapture() });
    return false;
  }
  return false;
});
