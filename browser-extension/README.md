# PinboardShot Chrome extension (development build)

This unpacked Manifest V3 extension captures ordinary HTTP(S) pages after the user explicitly starts it from the toolbar popup or the configured keyboard shortcut. It reads only the active tab granted by that action. It does not use the debugger API, inspect other tabs, or send page content over the network.

The extension scrolls the document root with smooth scrolling and scroll snapping disabled temporarily. It waits for the actual scroll position to settle, takes viewport PNG tiles at least 650 ms apart, and sends each tile with its CSS `scrollY` and viewport geometry over Chrome Native Messaging to `com.ryanwang.pinboardshot.browser_capture`. The App receives ordered PNG chunks and is responsible for joining the tiles. No page URL or title is sent.

Fixed and sticky elements stay visible in the first tile, then are hidden to prevent them repeating down the image. Their inline visibility values, the document scroll behavior, scroll position, and scroll-snap settings are restored after success, cancellation, tab switching, or capture failure. Press Escape in the page or use Cancel in the popup to stop. If the viewport changes, scroll stalls, coordinate coverage has a gap, the native host disconnects, or a time/pixel/tile budget is exceeded, the extension reports an incomplete capture and sends `cancel` rather than claiming success.

The guardrails currently cap one capture at five minutes, 250 million estimated physical tile pixels including overlap, 32 million pixels per tile, and 1,200 viewport tiles. Chrome limits visible-tab capture frequency; the extension spaces captures by at least 650 ms. It waits for visible fonts and images for a bounded interval of up to about 1.2 seconds per viewport. A slow external image may still be loading when its tile is captured. If the host reports that the screenshot was saved but the app failed to open it, the extension preserves that result and tells the user to check PinboardShot and retry; it does not report the capture as lost.

## Load for development

1. Build/install the PinboardShot desktop app version that includes the Native Messaging host.
   In App Settings → General → Chrome Web Capture, complete the local connection setup first.
2. Open `chrome://extensions`, enable Developer mode, and choose **Load unpacked** for this directory.
3. Pin the extension, open an HTTP(S) page, then click the extension and choose **Capture long page**. On Mac, `⌘⇧Y` is the suggested shortcut and can be changed in Chrome's extension shortcut settings.

The manifest's development public key gives this unpacked build a stable development extension ID. A Chrome Web Store release needs the store-assigned ID and matching Native Messaging host allowlist. This repository does not silently install or enable extensions, and the browser does not allow a regular macOS installer to silently enable a Web Store extension.

## Tests

Run `node --test browser-extension/tests/*.test.mjs` from the repository root. The mock Chrome integration tests validate extension orchestration and Native Messaging, but do not replace a manual capture against real Chrome pages.
