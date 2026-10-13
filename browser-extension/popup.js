const CHANNEL = "pinboardshot.capture";
let connectionState = { status: "checking" };
let currentCaptureState = { status: "idle" };
let pendingAction = null;
let pendingOriginStatus = null;
let actionStateWaiter = null;
let actionError = "";
let stateRevision = 0;
const storedLanguage = localStorage.getItem("pinboardshot.language");
let language = storedLanguage || (navigator.language.toLowerCase().startsWith("zh") ? "zh" : "en");
const strings = {
  zh: {
    title: "网页长截图", finishHint: "停止会保存已截取的部分；取消会丢弃本次截图。",
    connection_checking: "正在检测本机 PinboardShot…", connection_connected: "已连接本机 PinboardShot",
    connection_disconnected: "独立模式 · 未连接 App，截图可直接保存 PNG",
    connection_unsupported: "独立模式 · App 需更新，截图可直接保存 PNG",
    capturingBadge: "正在截图", pausedBadge: "已暂停", completeBadge: "已完成", stoppedBadge: "已停止",
    completeTitle: "截图已完成", stoppedTitle: "已保存截取部分", cancelledTitle: "本次截图已取消", stoppedEmptyTitle: "未截取到内容",
    cancel: "取消并丢弃", captureAgain: "再截一次", retryCapture: "重试截图", starting: "正在开始…", resuming: "正在继续…", saving: "正在保存…", action_failed: "操作未完成，请重试。", action_unconfirmed: "尚未确认操作结果，请检查当前截图状态。", capture_failed: "无法开始截图，请重试。",
    description: "按网页真实滚动坐标截取长页面，并发送到 PinboardShot。",
    description_browser: "无需 App，按网页真实滚动坐标截取长页面，在浏览器内拼接并保存 PNG。",
    saveAs: "保存时选择位置", start_browser: "截图并保存 PNG",
    complete_browser: "PNG 已下载。可在 Chrome 下载列表中查看。",
    stopped_browser: "已停止，截取的部分已保存为 PNG。",
    browser_image_too_large: "图片超过独立模式的安全上限（单边 32767 像素、总计 3200 万像素）。请缩小窗口，或连接 App 后重试。",
    browser_image_failed: "浏览器无法拼接 PNG，请缩小截图范围后重试。",
    invalid_png: "浏览器截图不是有效的 PNG，已停止。", invalid_png_geometry: "截图尺寸与页面不一致，已停止。",
    inconsistent_tile_geometry: "截图尺寸发生变化，已停止以避免拼接错位。", first_tile_must_start_at_top: "截图未从页面顶部开始，已停止。", capture_gap: "截图存在未覆盖的间隙，已停止。",
    browser_download_failed: "PNG 未能保存，请检查 Chrome 下载设置后重试。",
    browser_download_timeout: "保存等待超时。请重新截图，并及时完成保存位置选择。",
    start: "开始网页长截图", pause: "暂停截图", resume: "继续截图", pausing: "正在暂停…", paused: "截图已暂停，继续时会回到暂停前的截取位置。", stop: "停止并保存", stopped: "已停止，截取的部分已发送到 PinboardShot。", stopped_empty: "已停止，没有截取到内容。", shortcut: "快捷键：⌘⇧Y（Mac） / Ctrl+Shift+Y",
    working: "正在截取…", preparing: "正在准备…", cancelling: "正在取消…", stopping: "正在停止并保存已截取的部分…", complete: "截图已发送到 PinboardShot。",
    cancelled: "已取消，本次截图已丢弃。", idle: "页面尚未开始截图。", error: "截图失败：",
    unsupported_page: "此页面类型不支持截图。请打开普通网页。",
    invoke_on_current_tab: "请在当前网页点击 Chrome 工具栏的 PinboardShot 图标，再开始截图。",
    screenshot_timeout: "浏览器截图长时间没有响应，已停止。请刷新网页后重试。",
    page_response_timeout: "网页长时间没有响应截图请求，已停止。请刷新网页后重试。",
    tab_query_timeout: "Chrome 长时间没有响应标签页检查，已停止。请重试。",
    active_tab_changed: "当前 Chrome 标签页或窗口发生切换，已取消以避免截错页面。",
    capture_position_changed: "截图时页面滚动位置发生变化，已取消以避免坐标错位。",
    pixel_budget_exceeded: "页面过长，超过安全像素上限。",
    tile_budget_exceeded: "截图尺寸超过安全上限，请缩小浏览器窗口或分段截取。",
    time_budget_exceeded: "截图超过最长时限，已停止并标记为不完整。",
    gap_detected: "页面滚动出现间隙，已停止，未提交不完整截图。",
    incomplete_coverage: "页面未完整覆盖，已停止，未提交不完整截图。",
    native_disconnected: "无法连接 PinboardShot。请在 App 设置 → 通用 → Chrome 网页长截图中完成连接后重试。",
    native_protocol_unsupported: "当前 PinboardShot 版本不支持截图暂停与停止。请更新 App 后重试。",
    capture_saved_app_open_failed: "截图已保留在 PinboardShot 中，但 App 未能自动打开。请检查 App 后重试。",
    scroll_stalled: "网页无法继续滚动，已停止。",
    viewport_changed: "浏览器页面尺寸发生变化，已取消。",
    horizontal_scroll_unsupported: "当前页面存在水平滚动，长截图暂不支持。",
    scroll_did_not_settle: "网页滚动后画面未稳定，已取消以避免断层。",
    scroll_position_unexpected: "网页没有滚动到预期位置，已取消。",
    capture_already_active: "已有截图任务正在运行。",
    multiple_scroll_regions: "页面有多个主要滚动区域，暂无法确定完整截图范围。请单独打开目标内容。",
    scroll_container_not_visible: "目标滚动区域未完整显示或存在缩放变换，请调整页面后重试。",
    scroll_container_changed: "目标滚动区域已被网页替换，请重试。",
    page_structure_too_large: "网页结构过于复杂，已停止以避免漏截内容。",
    fixed_overlay_too_large: "悬浮内容遮挡了大部分页面，请关闭遮挡后重试。",
    visible_resource_timeout: "可见图片或字体未能及时加载，未提交可能缺少内容的截图。请等待页面加载后重试。",
    visible_resource_failed: "可见图片或字体加载失败，未提交可能缺少内容的截图。",
    invalid_crop_geometry: "滚动区域与截图尺寸不一致，已停止以避免裁切错误。"
  },
  en: {
    title: "Webpage capture", finishHint: "Stop saves the captured portion. Cancel discards this capture.",
    connection_checking: "Checking the local PinboardShot app…", connection_connected: "Connected to PinboardShot",
    connection_disconnected: "Standalone · App disconnected; save directly as PNG",
    connection_unsupported: "Standalone · App needs an update; save directly as PNG",
    capturingBadge: "Capturing", pausedBadge: "Paused", completeBadge: "Complete", stoppedBadge: "Stopped",
    completeTitle: "Capture complete", stoppedTitle: "Captured portion saved", cancelledTitle: "Capture cancelled", stoppedEmptyTitle: "No content captured",
    cancel: "Cancel and discard", captureAgain: "Capture again", retryCapture: "Retry capture", starting: "Starting…", resuming: "Resuming…", saving: "Saving…", action_failed: "The action did not complete. Please retry.", action_unconfirmed: "The action is not yet confirmed. Check the current capture status.", capture_failed: "Could not start capture. Please retry.",
    description: "Capture a long web page using its actual scroll coordinates and send it to PinboardShot.",
    description_browser: "No app needed. Capture a long page, stitch it in your browser and save a PNG locally.",
    saveAs: "Choose where to save", start_browser: "Capture and save PNG",
    complete_browser: "PNG downloaded. Find it in Chrome’s downloads list.",
    stopped_browser: "Stopped. The captured portion was saved as a PNG.",
    browser_image_too_large: "Standalone image limit reached (32767 pixels per edge, 32 million pixels total). Reduce the window size or connect the app and retry.",
    browser_image_failed: "The browser could not stitch the PNG. Try a smaller capture.",
    invalid_png: "Chrome returned an invalid PNG. Capture stopped.", invalid_png_geometry: "The screenshot size does not match the page. Capture stopped.",
    inconsistent_tile_geometry: "The screenshot size changed. Capture stopped to avoid incorrect stitching.", first_tile_must_start_at_top: "Capture did not start at the top of the page.", capture_gap: "The capture contains an uncovered gap. Capture stopped.",
    browser_download_failed: "The PNG could not be saved. Check Chrome’s download settings and retry.",
    browser_download_timeout: "Saving timed out. Retry the capture and finish choosing a save location promptly.",
    start: "Capture long page", pause: "Pause capture", resume: "Resume capture", pausing: "Pausing…", paused: "Capture paused. Resuming returns to the saved capture position.", stop: "Stop and save", stopped: "Stopped. The captured portion was sent to PinboardShot.", stopped_empty: "Stopped before any content was captured.", shortcut: "Shortcut: ⌘⇧Y (Mac) / Ctrl+Shift+Y",
    working: "Capturing…", preparing: "Preparing…", cancelling: "Cancelling…", stopping: "Stopping and saving the captured portion…", complete: "Capture sent to PinboardShot.",
    cancelled: "Cancelled. This capture was discarded.", idle: "Ready to capture this page.", error: "Capture failed: ",
    unsupported_page: "This page type cannot be captured. Open a regular web page.",
    invoke_on_current_tab: "Click the PinboardShot icon in the Chrome toolbar on this tab, then start capture.",
    screenshot_timeout: "Chrome did not return the screenshot in time. Capture stopped. Reload the page and try again.",
    page_response_timeout: "The page did not respond to the capture request in time. Reload the page and try again.",
    tab_query_timeout: "Chrome did not respond to the tab check in time. Please try again.",
    active_tab_changed: "The active Chrome tab or window changed. Capture cancelled to avoid capturing another page.",
    capture_position_changed: "The page moved while the screenshot was taken. Capture cancelled to preserve tile coordinates.",
    pixel_budget_exceeded: "The page exceeds the safe pixel limit.",
    tile_budget_exceeded: "The capture exceeds the safe image size. Reduce the browser window or capture a shorter section.",
    time_budget_exceeded: "Capture exceeded its time limit and was stopped as incomplete.",
    gap_detected: "A gap was detected while scrolling. The incomplete capture was stopped.",
    incomplete_coverage: "The page was not fully covered. The incomplete capture was stopped.",
    native_disconnected: "Could not connect to PinboardShot. Complete the connection in App Settings → General → Chrome Web Capture, then try again.",
    native_protocol_unsupported: "This PinboardShot version does not support capture pause and stop. Update the app and try again.",
    capture_saved_app_open_failed: "The capture is saved in PinboardShot, but the app could not open automatically. Check the app and try again.",
    scroll_stalled: "The page stopped scrolling before the end.",
    viewport_changed: "The browser viewport changed. Capture cancelled.",
    horizontal_scroll_unsupported: "This page uses horizontal scrolling, which is not supported for long capture.",
    scroll_did_not_settle: "The page did not settle after scrolling. Capture cancelled to avoid gaps.",
    scroll_position_unexpected: "The page did not reach the expected scroll position. Capture cancelled.",
    capture_already_active: "A capture is already running.",
    multiple_scroll_regions: "This page has multiple main scrolling regions. Open the target content separately before capturing.",
    scroll_container_not_visible: "The scrolling region is clipped or transformed. Adjust the page and retry.",
    scroll_container_changed: "The page replaced the scrolling region. Please retry.",
    page_structure_too_large: "The page structure is too complex to capture without risking missing content.",
    fixed_overlay_too_large: "A floating overlay covers most of the page. Dismiss it and retry.",
    visible_resource_timeout: "Visible images or fonts did not load in time. An incomplete capture was not submitted; wait and retry.",
    visible_resource_failed: "A visible image or font failed to load. An incomplete capture was not submitted.",
    invalid_crop_geometry: "The scrolling region does not match the screenshot size. Capture stopped to avoid incorrect cropping."
  }
};
const $ = id => document.getElementById(id);
const languageButton = $("language");
const startButton = $("start");
const stopButton = $("stop");
const cancelButton = $("cancel");
const pauseButton = $("pause");
const progressArea = $("progressArea");
const message = $("message");
const saveAsInput = $("saveAs");
saveAsInput.checked = localStorage.getItem("pinboardshot.saveAs") === "true";

function tr(key) { return strings[language][key] || key.replaceAll("_", " "); }

function renderState(state) {
  currentCaptureState = state || { status: "idle" };
  const status = state?.status || "idle";
  $("panel").setAttribute("data-state", status);
  const active = ["preparing", "capturing", "pausing", "paused", "stopping", "saving", "cancelling"].includes(status);
  const busy = pendingAction !== null;
  const browserMode = active && state?.mode ? state.mode === "browser" : connectionState.status !== "connected";
  $("panel").setAttribute("data-mode", browserMode ? "browser" : "app");
  $("description").textContent = tr(browserMode ? "description_browser" : "description");
  $("saveOptions").hidden = !browserMode || active || busy;
  saveAsInput.disabled = active || busy;
  startButton.disabled = active || busy;
  startButton.hidden = active;
  $("startLabel").textContent = tr(pendingAction === "start" ? "starting" : status === "error" ? "retryCapture" : ["complete", "stopped"].includes(status) ? "captureAgain" : browserMode ? "start_browser" : "start");
  stopButton.hidden = !active || ["saving", "cancelling"].includes(status);
  stopButton.disabled = busy || status === "stopping";
  $("stopLabel").textContent = tr(pendingAction === "stop" || status === "stopping" ? "saving" : "stop");
  cancelButton.hidden = !active || ["stopping", "cancelling"].includes(status);
  cancelButton.disabled = busy;
  cancelButton.textContent = tr(pendingAction === "cancel" ? "cancelling" : "cancel");
  pauseButton.hidden = !["capturing", "pausing", "paused"].includes(status);
  pauseButton.disabled = busy || status === "pausing";
  $("pauseLabel").textContent = tr(pendingAction === "togglePause" ? (pendingOriginStatus === "paused" ? "resuming" : "pausing") : status === "pausing" ? "pausing" : status === "paused" ? "resume" : "pause");
  pauseButton.setAttribute("data-mode", status === "paused" ? "resume" : "pause");
  $("captureCard").setAttribute("aria-busy", String(active || busy));
  $("captureActions").hidden = !active || status === "cancelling";
  // Progress describes a running task; terminal results must not look like a paused capture.
  progressArea.hidden = !active;
  const progress = active ? Math.max(0, Math.min(100, state?.progress || 0)) : 0;
  $("progressBar").style.width = `${progress}%`;
  $("progressPercent").textContent = active ? `${progress}%` : "";
  $("progressPercent").hidden = !active;
  $("progressTrack").setAttribute("aria-valuenow", String(progress));
  $("progressText").textContent = active ? tr(status === "capturing" ? "working" : status) : "";
  const badgeKey = { capturing: "capturingBadge", paused: "pausedBadge", complete: "completeBadge", stopped: "stoppedBadge", stopped_empty: "stoppedBadge" }[status];
  $("statusBadge").hidden = !badgeKey || pendingAction === "start";
  $("statusBadge").textContent = badgeKey ? tr(badgeKey) : "";
  $("finishHint").hidden = !active || ["stopping", "cancelling"].includes(status);
  const terminal = ["complete", "cancelled", "stopped", "stopped_empty"].includes(status);
  const titleKey = { complete: "completeTitle", stopped: "stoppedTitle", cancelled: "cancelledTitle", stopped_empty: "stoppedEmptyTitle" }[status];
  $("resultTitle").hidden = !titleKey || pendingAction === "start";
  $("resultTitle").textContent = titleKey ? tr(titleKey) : "";
  const symbol = { pausing: "pause", paused: "pause", complete: "check", stopped: "check", cancelled: "x", stopped_empty: "warning", error: "warning" }[status];
  $("sceneBadge").hidden = !symbol || pendingAction === "start";
  $("sceneBadge").setAttribute("data-symbol", symbol || "");
  message.classList.toggle("error", status === "error" || !!actionError);
  message.classList.toggle("success", !actionError && ["complete", "stopped"].includes(status));
  const resultKey = state?.mode === "browser" && ["complete", "stopped"].includes(status) ? `${status}_browser` : status;
  message.textContent = actionError ? tr(actionError) : status === "error" ? `${tr("error")}${tr(state.error)}` : terminal && pendingAction !== "start" ? tr(resultKey) : "";
}

function applyState(state) {
  stateRevision++;
  actionError = "";
  renderState(state);
  if (actionStateWaiter && actionStateObserved()) actionStateWaiter();
}

function actionStateObserved() {
  const status = currentCaptureState.status;
  if (!["preparing", "capturing", "pausing", "paused", "stopping", "saving", "cancelling"].includes(status)) return true;
  if (pendingAction === "stop") return ["stopping", "saving"].includes(status);
  if (pendingAction === "togglePause") return pendingOriginStatus === "paused" ? status === "capturing" : ["pausing", "paused"].includes(status);
  return true;
}

async function waitForActionState() {
  if (actionStateObserved()) return;
  // Native control acknowledgement precedes the next state poll. Keep controls locked
  // until the requested transition is observed, rather than immediately toggling again.
  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      actionStateWaiter = null;
      reject(new Error("action_unconfirmed"));
    }, 5000);
    actionStateWaiter = () => {
      clearTimeout(timer);
      actionStateWaiter = null;
      resolve();
    };
  });
}

async function refreshState() {
  const revision = stateRevision;
  const reply = await chrome.runtime.sendMessage({ channel: CHANNEL, type: "stateRequest" }).catch(() => null);
  // A broadcast received during the request is newer than that request's snapshot.
  if (reply?.ok && reply.state && revision === stateRevision) applyState(reply.state);
}

async function requestAction(type, button) {
  if (pendingAction || button.disabled || button.hidden) return;
  pendingAction = type;
  pendingOriginStatus = currentCaptureState.status;
  actionError = "";
  renderState(currentCaptureState);
  try {
    const reply = await chrome.runtime.sendMessage({ channel: CHANNEL, type, ...(type === "start" ? { saveAs: saveAsInput.checked } : {}) });
    if (!reply?.ok) {
      actionError = reply?.error || (type === "start" ? "capture_failed" : "action_failed");
    } else {
      await refreshState();
      if (["stop", "togglePause"].includes(type)) await waitForActionState();
    }
  } catch (error) {
    actionError = error?.message === "action_unconfirmed" ? "action_unconfirmed" : type === "start" ? "capture_failed" : "action_failed";
  } finally {
    pendingAction = null;
    pendingOriginStatus = null;
    renderState(currentCaptureState);
  }
}

function renderConnection(connection) {
  connectionState = connection;
  $("panel").setAttribute("data-connection", connection.status);
  $("connection").textContent = tr(`connection_${connection.status}`);
  $("connection").classList.toggle("error", false);
  renderState(currentCaptureState);
}

async function checkConnection() {
  const reply = await chrome.runtime.sendMessage({ channel: CHANNEL, type: "connectionRequest" }).catch(() => null);
  renderConnection(reply?.ok && reply.connection ? reply.connection : { status: "disconnected" });
}

function renderLanguage() {
  document.documentElement.lang = language === "zh" ? "zh-Hans" : "en";
  languageButton.textContent = language === "zh" ? "EN" : "中文";
  $("title").textContent = tr("title");
  $("finishHint").textContent = tr("finishHint");
  $("saveAsLabel").textContent = tr("saveAs");
  $("description").textContent = tr("description");
  $("startLabel").textContent = tr("start");
  $("stopLabel").textContent = tr("stop");
  cancelButton.textContent = tr("cancel");
  $("shortcut").textContent = tr("shortcut");
  renderConnection(connectionState);
}

languageButton.addEventListener("click", () => {
  language = language === "zh" ? "en" : "zh";
  localStorage.setItem("pinboardshot.language", language);
  renderLanguage();
});
startButton.addEventListener("click", () => requestAction("start", startButton));
stopButton.addEventListener("click", () => requestAction("stop", stopButton));
cancelButton.addEventListener("click", () => requestAction("cancel", cancelButton));
pauseButton.addEventListener("click", () => requestAction("togglePause", pauseButton));
saveAsInput.addEventListener("change", () => localStorage.setItem("pinboardshot.saveAs", String(saveAsInput.checked)));
chrome.runtime.onMessage.addListener(message => {
  if (message?.channel === CHANNEL && message.type === "state") applyState(message.state);
  if (message?.channel === CHANNEL && message.type === "connection") renderConnection(message.connection);
});

renderLanguage();
void refreshState();
void checkConnection();
// Retry while this panel is visible so installing or reopening the app needs no reload.
setInterval(() => { if (!document.hidden) void checkConnection(); }, 5000);
