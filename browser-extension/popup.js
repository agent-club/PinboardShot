const CHANNEL = "pinboardshot.capture";
const storedLanguage = localStorage.getItem("pinboardshot.language");
let language = storedLanguage || (navigator.language.toLowerCase().startsWith("zh") ? "zh" : "en");
const strings = {
  zh: {
    title: "网页长截图", finishHint: "停止截图会保存已截取的部分，并发送到 PinboardShot。",
    capturingBadge: "正在截图", pausedBadge: "已暂停", completeBadge: "已完成", stoppedBadge: "已停止",
    cancel: "取消截图",
    description: "按网页真实滚动坐标截取长页面，并发送到 PinboardShot。",
    start: "开始网页长截图", pause: "暂停截图", resume: "继续截图", pausing: "正在暂停…", paused: "截图已暂停，继续时会回到暂停前的截取位置。", stop: "停止截图", stopped: "截图已停止，已保留已截取的部分。", stopped_empty: "截图已停止，没有截取到内容。", shortcut: "快捷键：⌘⇧Y（Mac） / Ctrl+Shift+Y",
    working: "正在截取…", preparing: "正在准备…", cancelling: "正在取消…", stopping: "正在停止并保存已截取的部分…", complete: "截图已发送到 PinboardShot。",
    cancelled: "截图已取消。", idle: "页面尚未开始截图。", error: "截图失败：",
    unsupported_page: "此页面类型不支持截图。请打开普通网页。",
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
    capture_already_active: "已有截图任务正在运行。"
  },
  en: {
    title: "Webpage capture", finishHint: "Stop saves the captured portion and sends it to PinboardShot.",
    capturingBadge: "Capturing", pausedBadge: "Paused", completeBadge: "Complete", stoppedBadge: "Stopped",
    cancel: "Cancel capture",
    description: "Capture a long web page using its actual scroll coordinates and send it to PinboardShot.",
    start: "Capture long page", pause: "Pause capture", resume: "Resume capture", pausing: "Pausing…", paused: "Capture paused. Resuming returns to the saved capture position.", stop: "Stop capture", stopped: "Capture stopped. The captured portion was saved.", stopped_empty: "Capture stopped before any content was captured.", shortcut: "Shortcut: ⌘⇧Y (Mac) / Ctrl+Shift+Y",
    working: "Capturing…", preparing: "Preparing…", cancelling: "Cancelling…", stopping: "Stopping and saving the captured portion…", complete: "Capture sent to PinboardShot.",
    cancelled: "Capture cancelled.", idle: "Ready to capture this page.", error: "Capture failed: ",
    unsupported_page: "This page type cannot be captured. Open a regular web page.",
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
    capture_already_active: "A capture is already running."
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

function tr(key) { return strings[language][key] || key.replaceAll("_", " "); }

function renderState(state) {
  const status = state?.status || "idle";
  const active = ["preparing", "capturing", "pausing", "paused", "stopping", "cancelling"].includes(status);
  startButton.disabled = active;
  startButton.hidden = active;
  stopButton.hidden = !active || status === "cancelling";
  stopButton.disabled = status === "stopping";
  cancelButton.hidden = !active || ["stopping", "cancelling"].includes(status);
  pauseButton.hidden = !["capturing", "pausing", "paused"].includes(status);
  pauseButton.disabled = status === "pausing";
  pauseButton.textContent = tr(status === "paused" ? "resume" : "pause");
  progressArea.hidden = !active && !["complete", "cancelled", "stopped", "stopped_empty"].includes(status);
  const progress = Math.max(0, Math.min(100, state?.progress || 0));
  $("progressBar").style.width = `${progress}%`;
  $("progressPercent").textContent = `${progress}%`;
  $("progressPercent").hidden = progressArea.hidden;
  $("progressText").textContent = status === "capturing" ? tr("working") : tr(status);
  const badgeKey = { capturing: "capturingBadge", paused: "pausedBadge", complete: "completeBadge", stopped: "stoppedBadge", stopped_empty: "stoppedBadge" }[status];
  $("statusBadge").hidden = !badgeKey;
  $("statusBadge").textContent = badgeKey ? tr(badgeKey) : "";
  $("finishHint").hidden = !active || status === "cancelling";
  message.classList.toggle("error", status === "error");
  message.textContent = status === "error" ? `${tr("error")}${tr(state.error)}` : "";
}

function renderLanguage() {
  document.documentElement.lang = language === "zh" ? "zh-Hans" : "en";
  languageButton.textContent = language === "zh" ? "EN" : "中文";
  $("title").textContent = tr("title");
  $("finishHint").textContent = tr("finishHint");
  $("description").textContent = tr("description");
  startButton.textContent = tr("start");
  stopButton.textContent = tr("stop");
  cancelButton.textContent = tr("cancel");
  $("shortcut").textContent = tr("shortcut");
  chrome.runtime.sendMessage({ channel: CHANNEL, type: "stateRequest" }).then(reply => {
    if (reply?.ok) renderState(reply.state);
  }).catch(() => {});
}

languageButton.addEventListener("click", () => {
  language = language === "zh" ? "en" : "zh";
  localStorage.setItem("pinboardshot.language", language);
  renderLanguage();
});
startButton.addEventListener("click", async () => {
  message.classList.remove("error");
  message.textContent = "";
  const reply = await chrome.runtime.sendMessage({ channel: CHANNEL, type: "start" }).catch(() => null);
  if (reply?.ok) {
    // A side panel stays open alongside the page throughout manual capture.
    // Opening/closing it mid-capture would change the page viewport geometry.
    return;
  }
  if (!reply?.ok) {
    message.classList.add("error");
    message.textContent = `${tr("error")}${tr(reply?.error || "capture_failed")}`;
  }
});
stopButton.addEventListener("click", () => chrome.runtime.sendMessage({ channel: CHANNEL, type: "stop" }).catch(() => {}));
cancelButton.addEventListener("click", () => chrome.runtime.sendMessage({ channel: CHANNEL, type: "cancel" }).catch(() => {}));
pauseButton.addEventListener("click", () => chrome.runtime.sendMessage({ channel: CHANNEL, type: "togglePause" }).catch(() => {}));
chrome.runtime.onMessage.addListener(message => {
  if (message?.channel === CHANNEL && message.type === "state") renderState(message.state);
});

renderLanguage();
