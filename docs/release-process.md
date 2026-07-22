# PinboardShot Release Process

Use this runbook when publishing a new PinboardShot GitHub Release, Sparkle update, and manual-install DMG.

## Scope

This process publishes public release assets only. Do not upload credentials, local configuration, logs, raw source snapshots, or development folders. The Sparkle private key and Apple notarization credentials must stay in Keychain or the release system secret store.

## Inputs

- Version: semantic version, for example `0.5.8`.
- Build: positive integer, for example `30`.
- Bilingual release notes: Chinese first, English second.
- Required local credentials:
  - Developer ID Application certificate.
  - Notary profile, default `PinboardShot-notary`.
  - Sparkle signing key in the configured local Keychain account.

## Preflight

1. Confirm the target version and build are newer than the latest GitHub Release.
2. Confirm `Resources/Info.plist` has matching values:

   ```bash
   plutil -replace CFBundleShortVersionString -string <version> Resources/Info.plist
   plutil -replace CFBundleVersion -string <build> Resources/Info.plist
   ```

3. Run the app test suite:

   ```bash
   swift test
   ```

4. Check Git state and keep unrelated changes out of the release commit:

   ```bash
   git status --short --untracked-files=all
   ```

## Build Assets

Run the release artifact CLI:

```bash
./scripts/release-artifacts.sh <version> <build>
```

The script performs:

- Release build.
- Developer ID signing.
- Apple notarization for the app.
- Stapling and Gatekeeper validation for the app.
- Sparkle ZIP and `appcast.xml` generation.
- DMG creation, Developer ID signing, Apple notarization, stapling, and Gatekeeper validation.
- SHA-256 output for ZIP, DMG, and appcast.
- ZIP inspection to ensure no `Sources`, `Tests`, `website`, `Package.swift`, `.env`, or `AGENTS.md` entries are present.

If the DMG is rejected with `source=no usable signature`, the DMG itself was not signed before notarization. `release-artifacts.sh` signs the DMG before submission; do not upload an unsigned DMG.

## Release Notes

GitHub Release notes must be bilingual and use this order:

```markdown
## 中文

PinboardShot <version>（build <build>）...

### 更新内容

- ...

### 兼容性与安装

- 支持 macOS 14 或更高版本，包含 Apple Silicon 与 Intel 架构。
- 新用户可下载 DMG，打开后将 PinboardShot 拖入 Applications。
- 已安装用户可继续使用应用内更新。

### 已知限制

- ...

### SHA-256

- `PinboardShot-<version>-<build>.zip`: `<sha>`
- `PinboardShot-<version>-<build>.dmg`: `<sha>`
- `appcast.xml`: `<sha>`

## English

PinboardShot <version> (build <build>) ...

### What's new

- ...

### Compatibility and installation

- Requires macOS 14 or later and includes both Apple Silicon and Intel architectures.
- New users can download the DMG, open it, and drag PinboardShot into Applications.
- Existing users can continue to use the in-app updater.

### Known limitation

- ...

### SHA-256

- `PinboardShot-<version>-<build>.zip`: `<sha>`
- `PinboardShot-<version>-<build>.dmg`: `<sha>`
- `appcast.xml`: `<sha>`
```

## Publish GitHub Release

Create the public Release and upload all three assets:

```bash
gh release create "v<version>" \
  ".build/update-feed/PinboardShot-<version>-<build>.zip" \
  ".build/update-feed/PinboardShot-<version>-<build>.dmg" \
  ".build/update-feed/appcast.xml" \
  --repo agent-club/PinboardShot \
  --target <branch-or-commit> \
  --title "PinboardShot <version>" \
  --notes-file <release-notes-file> \
  --latest
```

Do not overwrite or delete an existing public Release without explicit user confirmation.

## Post-Publish Verification

1. Inspect the Release:

   ```bash
   gh release view "v<version>" \
     --repo agent-club/PinboardShot \
     --json tagName,isDraft,isPrerelease,publishedAt,url,assets
   ```

2. Download public assets using anonymous URLs and compare SHA-256 with the local artifacts:

   ```bash
   curl -L --fail --silent --show-error \
     -o "/private/tmp/PinboardShot-<version>-<build>.public.zip" \
     "https://github.com/agent-club/PinboardShot/releases/download/v<version>/PinboardShot-<version>-<build>.zip"
   curl -L --fail --silent --show-error \
     -o "/private/tmp/PinboardShot-<version>-<build>.public.dmg" \
     "https://github.com/agent-club/PinboardShot/releases/download/v<version>/PinboardShot-<version>-<build>.dmg"
   curl -L --fail --silent --show-error \
     -o "/private/tmp/PinboardShot-<version>.appcast.public.xml" \
     "https://github.com/agent-club/PinboardShot/releases/download/v<version>/appcast.xml"
   shasum -a 256 \
     "/private/tmp/PinboardShot-<version>-<build>.public.zip" \
     "/private/tmp/PinboardShot-<version>-<build>.public.dmg" \
     "/private/tmp/PinboardShot-<version>.appcast.public.xml"
   ```

3. Confirm appcast points at the new ZIP:

   ```bash
   rg -n "<version>|<build>|PinboardShot-<version>-<build>\\.zip|sparkle:edSignature" \
     "/private/tmp/PinboardShot-<version>.appcast.public.xml"
   ```

4. Confirm repository visibility is public:

   ```bash
   gh repo view agent-club/PinboardShot --json visibility,url,defaultBranchRef
   ```

5. Clean temporary public downloads after verification.

## Website Metadata

Update `website/content/current-release.json` with:

- version and build
- release URL
- ZIP, DMG, and appcast URLs
- final SHA-256 values
- bilingual release highlights

Then validate:

```bash
npm run check:app-version
npm test
```

Run those commands from `website/`.

Commit only intended public metadata and workflow files. If the website deployment workflow only runs on `main`, push the branch and open a PR to `main`; merging that PR is what updates the public website.

## Local Install Verification

After publishing an app-changing release, install the newly built app locally:

1. Quit PinboardShot.
2. Move the old `/Applications/PinboardShot.app` to a temporary backup path.
3. Copy `.build/app/PinboardShot.app` to `/Applications/PinboardShot.app`.
4. Launch `/Applications/PinboardShot.app`.
5. Verify:

   ```bash
   plutil -p /Applications/PinboardShot.app/Contents/Info.plist
   codesign --verify --deep --strict /Applications/PinboardShot.app
   pgrep -x PinboardShot
   ps -p <pid> -o pid= -o comm=
   ```

The running path must be `/Applications/PinboardShot.app/Contents/MacOS/PinboardShot`.

## Final Report Checklist

Include:

- Release URL.
- PR URL, if website metadata is not already on `main`.
- Version/build.
- Uploaded assets.
- Final SHA-256 values.
- Validation commands and results.
- Whether `/Applications/PinboardShot.app` was updated and verified.
- Any unrelated local changes intentionally left untouched.
