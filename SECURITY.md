# Security Policy

## Supported Versions

PinboardShot is a local-first macOS app. Security fixes are normally released for the latest public version only.

| Version | Supported |
| --- | --- |
| Latest public release | Yes |
| Older releases | Best effort |

## Reporting a Vulnerability

Please report security issues privately instead of opening a public issue.

Use GitHub's private vulnerability reporting for this repository when available:

https://github.com/agent-club/PinboardShot/security/advisories/new

If private vulnerability reporting is unavailable, open a minimal public issue that says you need a private contact channel. Do not include exploit details, screenshots with sensitive content, credentials, logs, or user data in the public issue.

## Scope

Security-relevant areas include:

- Screenshot capture, annotation, pinning, history, clipboard, and local storage behavior.
- macOS Screen & System Audio Recording permission handling.
- Software update checks, Sparkle appcast handling, update package verification, and download URLs.
- Website download links and published release artifacts.
- Build, signing, notarization, and release scripts.

Out of scope:

- Vulnerabilities in third-party services that host releases, downloads, notarization, or CDN delivery, unless PinboardShot misconfigures its own integration.
- Issues caused by modifying local builds, disabling macOS security controls, or installing unofficial packages.
- Social engineering, phishing, or physical access attacks.

## Privacy Boundary

PinboardShot does not require an account, does not provide cloud sync, and does not include analytics or advertising SDKs. Screenshots, annotations, pins, recent history, optional invisible watermark records, shortcuts, and preferences are processed locally on the user's Mac. Network access is used for software update checks and update downloads.

See the public privacy policy:

https://pinboardshot.agentclub.dev/privacy

## Disclosure Process

After a report is received, the project will aim to:

1. Acknowledge the report within 7 days.
2. Confirm whether the issue is reproducible and in scope.
3. Prepare a fix and release notes when the issue affects users.
4. Credit the reporter if requested and appropriate.

Please allow time for investigation before public disclosure, especially for update, signing, notarization, or installer issues.
