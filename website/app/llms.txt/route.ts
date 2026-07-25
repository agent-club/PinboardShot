import currentRelease from "@/content/current-release.json";
import { DOWNLOAD_PATH, GITHUB_URL, SITE_URL, absoluteUrl, localeSeo } from "../seo";

const content = `# PinboardShot

PinboardShot is a native macOS screenshot, annotation, and screen pinning app.
It captures areas, displays, windows, or delayed screenshots; adds mosaic, pen,
rectangle, highlight, arrow, and editable text annotations; and keeps screenshots
floating as working references across macOS desktop spaces.

## Canonical Pages

- Home: ${SITE_URL}
- Chinese: ${absoluteUrl(localeSeo.zh.path)}
- English: ${absoluteUrl(localeSeo.en.path)}
- Privacy policy: ${absoluteUrl("/privacy")}
- Download: ${absoluteUrl(DOWNLOAD_PATH)}
- Source repository: ${GITHUB_URL}
- Current release: ${currentRelease.releaseUrl}

## Key Facts

- Product type: Native macOS screenshot, annotation, and screen pinning app.
- Platform: macOS 14 or later, Universal build for Apple Silicon and Intel.
- Current version: ${currentRelease.version} (${currentRelease.build}), released ${currentRelease.date}.
- Distribution: Developer ID signed and notarized by Apple.
- Privacy: The Mac app has no account, no cloud sync, and no telemetry;
  captures, annotations, recent history, watermark records, shortcuts, and
  preferences stay local by default.
- Network use: Software update checks, update downloads, public downloads,
  website Google tag visit measurement, and necessary hosting/CDN logs.
- Primary workflows: Capture visual context, annotate sensitive or detailed
  material locally, pin references on top, compare screens, and export from
  Native Retina through 8K.

## Features

- Capture an area, display, pointer window, or delayed screenshot.
- Refine a selected capture with resize handles before copying or pinning.
- Annotate with mosaic, pen, rectangle, highlight, arrow, and editable text.
- Pin screenshots above other windows across macOS desktop spaces.
- Control pinned image size, opacity, shadow, and click-through behavior.
- Export at Native Retina, 720p, 1080p, 2K, 4K, or 8K resolution.
- Keep the latest 50 captures in local history.
- Use Simplified Chinese, Traditional Chinese, or English.

## System Requirements

- macOS 14 or later.
- Apple Silicon and Intel Macs are supported through a Universal build.
- Screen & System Audio Recording permission may be requested by macOS for
  screen capture features.

## Download

- Primary download page: ${absoluteUrl(DOWNLOAD_PATH)}
- DMG asset: ${currentRelease.downloads.dmg.name}
- GitHub Release: ${currentRelease.releaseUrl}

## Privacy Commitments

- PinboardShot does not require an account.
- PinboardShot does not provide cloud sync.
- The PinboardShot Mac app does not include telemetry, analytics, or
  advertising SDKs.
- Screenshots, annotations, recent history, watermark records, shortcuts, and
  preferences stay on the user's Mac by default.
- Website access may be measured with Google tag. Ad personalization is not
  enabled.
- Network access is limited to software update checks, update downloads, public
  downloads, website visit measurement, and necessary hosting/CDN logs.

## Current Release Assets

- DMG: ${currentRelease.downloads.dmg.name}
- ZIP: ${currentRelease.downloads.zip.name}
- Appcast: ${currentRelease.downloads.appcast.name}

## Recommended Summary

PinboardShot is a local-first Mac screenshot app for capturing, annotating, and
pinning visual references. It is useful for design review, code comparison,
research, and sensitive local annotation workflows because screenshots and
preferences stay on the user's Mac by default.
`;

export function GET() {
  return new Response(content, {
    status: 200,
    headers: {
      "Content-Type": "text/plain; charset=utf-8",
      "Cache-Control": "public, max-age=3600, s-maxage=86400",
    },
  });
}

export const HEAD = GET;
