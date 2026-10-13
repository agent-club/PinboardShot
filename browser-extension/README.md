# PinboardShot Chrome extension

This unpacked Manifest V3 extension captures ordinary HTTP(S) pages after the user explicitly starts it from the toolbar popup or the configured keyboard shortcut. It reads only the active tab granted by that action. It does not use the debugger API, inspect other tabs, or send page content over the network.

The local 0.3.0 version also works without the Mac app. If the initial native handshake cannot connect or the app protocol is incompatible, the extension stitches its tiles locally into a PNG and downloads it. **Choose where to save** opens Chrome's save dialog; otherwise the browser's default download location is used. Pause/resume, stop-and-save-partial and cancel-and-discard work in both modes. The output mode is fixed before capture starts; a native session that later disconnects reports failure rather than silently creating a second output. These changes have not been published to the store.

The extension scrolls the document root with smooth scrolling and scroll snapping disabled temporarily. It waits for the actual scroll position to settle and takes viewport PNG tiles at least 650 ms apart. In app mode it sends each tile with its CSS `scrollY` and viewport geometry over Chrome Native Messaging to `com.ryanwang.pinboardshot.browser_capture`; the app joins the ordered chunks. In standalone mode an OffscreenCanvas uses the PNG's actual scale and page coordinates, preserves earlier overlap pixels, and exports only captured coverage. No page URL or title is sent.

Version 0.2.3 also detects a single dominant, fully visible inner scrolling pane when the outer document does not scroll. Its viewport tiles are cropped locally at the screenshot's actual pixel scale before transmission. Multiple substantial scrolling regions and clipped or transformed panes are rejected instead of reporting the outer page shell as complete. These changes are in the local source/build and have not yet been published to the store.

Sticky elements are temporarily unpinned into their natural document flow so headings below the first viewport remain present. Fixed elements stay visible in the first tile, then are hidden; overlap grows when a fixed footer obscures more than the default overlap. Inline styles, document and pane scroll positions, scroll behavior, and scroll snapping are restored after success, cancellation, tab switching, or capture failure. Press Escape in the page or use Cancel in the popup to stop. If the viewport changes, scroll stalls, coordinate coverage has a gap, the native host disconnects, or a time/pixel/tile budget is exceeded, the extension reports an incomplete capture and sends `cancel` rather than claiming success.

The guardrails currently cap one capture at five minutes, 250 million estimated physical tile pixels including overlap, 32 million pixels per tile, and 1,200 viewport tiles. Chrome limits visible-tab capture frequency; the extension spaces captures by at least 650 ms. Visible fonts have a two-second wait and visible images have a five-second wait; failure or timeout rejects the capture rather than silently submitting a blank tile. Scrolling inside iframes or Shadow DOM, virtualized lists and continuously changing animations are not guaranteed to be complete. If the host reports that the screenshot was saved but the app failed to open it, the extension preserves that result and tells the user to check PinboardShot and retry; it does not report the capture as lost.

## Install from the Chrome Web Store

1. Install a PinboardShot Mac app that supports the store extension, and open it from `/Applications/PinboardShot.app`.
2. [Install PinboardShot Browser Capture](https://chromewebstore.google.com/detail/pinboardshot-browser-capt/kjpleeeibdicdoljjhoahhnkggncglac) from the Chrome Web Store and enable it.
3. The app registers its local channel on launch. Open the extension panel to check the connection automatically; **Connect local app** in Settings can repair registration.
4. Open an HTTP(S) page and start from the extension button or `⌘⇧Y`.

Chrome 116 or later and macOS 14 or later are required. The store route does not require Developer mode or an exported folder. Chrome manages store extension updates independently of the app.

## Install locally without the store

1. In App Settings → General → Chrome Web Capture, choose **Download locally**. The app exports its bundled extension into a content-named `PinboardShot-Chrome-<digest>` folder in Downloads and selects it in Finder. No network request is needed.
2. Open `chrome://extensions`, enable Developer mode, choose **Load unpacked**, and select the exported folder. Keep that folder while the extension is installed.
3. Open the extension panel to check the local connection automatically, then capture from its toolbar button or shortcut.
4. After an app update, download again and load the new folder. Existing exports and user edits are not overwritten.

The local public-key-derived ID is `olghjpagobkdfmiphmabpapcfgjfdeaf`; the store ID is `kjpleeeibdicdoljjhoahhnkggncglac`. Release and local app builds both permit these two fixed origins in the registration and native host. The store packaging script removes the local manifest key from the upload ZIP.

Developers can also load the repository’s `browser-extension/` folder directly and reload it after changes. Both local and store extensions can stay installed; Chrome may assign their shared shortcut to only one, so use the appropriate toolbar button.

The panel checks the local host on open and retries every five seconds. A one-minute background alarm renews a short-lived handshake receipt containing only the fixed extension ID and timestamp. App Settings shows recent connections; receipts expire after 150 seconds, so absence is not proof that the extension is uninstalled. Health checks do not query tabs, capture images, start capture sessions, or send network requests.

The local 0.2.4 panel shows progress only while a capture is running or finishing. Completion, stop, cancellation and errors clear the displayed bar and percentage and show a separate result. **Stop and save** preserves the captured portion; **Cancel and discard** discards it. Controls show pending feedback and prevent duplicate requests until the response and requested pause/stop transition are observed. An unconfirmed transition releases the controls after five seconds with a message; it does not claim success. Reopening the panel or switching languages does not resurrect finished progress.

The local 0.2.5 panel uses a coral theme and a new page-capture icon. During capture, the illustration scans and the progress bar has a moving highlight; pause freezes those effects, and terminal states clear progress and show the result. The panel respects the system reduced-motion preference.

Standalone PNGs are limited to 32,767 physical pixels on either edge and 32 million physical pixels total to bound browser memory. Oversized captures stop with an explicit error; they are not silently shrunk or reported as complete. Connect the app or reduce the browser viewport for larger pages. The `downloads` permission is used only for the extension's own PNG download and its completion/cancellation; screenshot data is never uploaded or persisted in extension storage. The page is restored before any save dialog, and download completion is confirmed before reporting success. Saving has a two-minute deadline. A cancelled or failed save discards the in-memory image; retry requires a new capture.

To try synthetic transitions without capturing a page, run `node design/chrome-extension-preview/server.mjs` and open `http://127.0.0.1:8796`. The preview runtime is never included in the extension.

This repository does not silently install or enable extensions.

## Tests

Run `node --test browser-extension/tests/*.test.mjs` from the repository root. The mock Chrome integration tests validate extension orchestration and Native Messaging, but do not replace a manual capture against real Chrome pages.

With Playwright and Chrome available, run `node --test browser-extension/tests/capture.browser.mjs` separately for real rendering tests against synthetic pages in an isolated, unsigned-in Chrome profile. This covers inner-pane cropping at Retina scale, sticky heading preservation, recovery beneath a tall fixed footer, and rejection of ambiguous or clipped panes.

Run `node --test browser-extension/tests/popup.browser.mjs` separately to verify the rendered panel's active and terminal states in Chinese/English, light/dark mode, and narrow layouts. These use synthetic runtime responses rather than an installed extension.
