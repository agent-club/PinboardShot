function downloadError(error) {
  return new Error(/USER_CANCELED|user cancel/i.test(String(error?.message || error)) ? "cancelled" : "browser_download_failed");
}

export async function saveBrowserCapture(chromeApi, blob, { saveAs = false, signal, timeoutMs = 120000 } = {}) {
  if (signal?.aborted) throw new Error("cancelled");
  const bytes = new Uint8Array(await blob.arrayBuffer());
  let binary = "";
  for (let offset = 0; offset < bytes.length; offset += 32768) {
    binary += String.fromCharCode(...bytes.subarray(offset, offset + 32768));
  }
  if (signal?.aborted) throw new Error("cancelled");
  const filename = `PinboardShot-${new Date().toISOString().replace(/[:.]/g, "-")}.png`;
  // Service workers cannot create blob URLs. The PNG stays local in a data URL.
  const url = `data:image/png;base64,${btoa(binary)}`;
  return new Promise((resolve, reject) => {
    let downloadId = null;
    let ended = false;
    const cancelDownload = () => {
      if (downloadId !== null) chromeApi.downloads.cancel(downloadId).catch(() => {});
    };
    const finish = error => {
      if (ended) return;
      ended = true;
      clearTimeout(timer);
      chromeApi.downloads.onChanged.removeListener(onChanged);
      signal?.removeEventListener("abort", onAbort);
      if (error) { cancelDownload(); reject(error); }
      else resolve(downloadId);
    };
    const onAbort = () => finish(new Error("cancelled"));
    const inspect = item => {
      if (item?.state === "complete") finish();
      else if (item?.state === "interrupted") finish(downloadError(item.error));
    };
    const onChanged = delta => {
      if (delta.id !== downloadId) return;
      inspect({ state: delta.state?.current, error: delta.error?.current });
    };
    const timer = setTimeout(() => finish(new Error("browser_download_timeout")), timeoutMs);
    chromeApi.downloads.onChanged.addListener(onChanged);
    signal?.addEventListener("abort", onAbort, { once: true });
    Promise.resolve().then(() => chromeApi.downloads.download({ url, filename, saveAs, conflictAction: "uniquify" })).then(async id => {
      if (!Number.isInteger(id) || id < 0) { finish(new Error("browser_download_failed")); return; }
      downloadId = id;
      // A save dialog can return after Cancel/timeout; cancel only our own download.
      if (ended) { cancelDownload(); return; }
      // Completion can arrive before download() returns its ID. Query that ID only.
      const [item] = await chromeApi.downloads.search({ id });
      if (!item) finish(new Error("browser_download_failed"));
      else inspect(item);
    }).catch(error => finish(downloadError(error)));
  });
}
