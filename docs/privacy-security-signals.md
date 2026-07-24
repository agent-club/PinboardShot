# Privacy and Security Signals

This checklist tracks free or community-based trust signals for PinboardShot. It is intentionally conservative: do not display a certification badge, seal, or listing until the project has actually earned it.

## Completed in Repository

- Public privacy policy: https://pinboardshot.agentclub.dev/privacy
- Security policy: `SECURITY.md`
- OpenSSF Scorecard workflow: `.github/workflows/scorecard.yml`
- README links to the privacy policy, security policy, and Scorecard status.
- Website trust-signal section that distinguishes public evidence from formal certification.

## OpenSSF Best Practices Badge

Official site: https://openssf.org/projects/best-practices-badge/

Status: pending external self-certification.

Recommended path:

1. Create or sign in to the OpenSSF Best Practices Badge web app.
2. Register `github.com/agent-club/PinboardShot`.
3. Complete the passing-level questionnaire first.
4. Use repository evidence where possible:
   - `README.md` for product description, build instructions, privacy notes, and release flow.
   - `LICENSE` for license status.
   - `SECURITY.md` for vulnerability reporting.
   - GitHub Releases for public release notes and artifacts.
   - `.github/workflows/scorecard.yml` for automated security posture scanning.
5. Add the official badge to `README.md` and the website only after the project receives a passing badge.

## OpenSSF Scorecard

Official viewer: https://scorecard.dev/viewer/?uri=github.com/agent-club/PinboardShot

Status: workflow configured; public badge pending first published result on the default branch.

The Scorecard badge is intentionally not shown in `README.md` yet. The badge image is served through Shields and returns `invalid repo path` until Scorecard has public data for the repository. Add it only after the default branch workflow publishes a result successfully.

## Website Checks

These checks provide public evidence, not certification.

- Mozilla HTTP Observatory: https://developer.mozilla.org/en-US/observatory
- SSL Labs SSL Server Test: https://www.ssllabs.com/ssltest/
- Blacklight website privacy inspector: https://themarkup.org/blacklight

Recommended release check:

1. Scan `https://pinboardshot.agentclub.dev`.
2. Record only grades, dates, and short remediation notes; do not persist large raw scan logs.
3. Treat Cloudflare challenge pages separately from the normal site response when interpreting results.
4. Do not claim "certified" based on these scans.

## Community Review Candidates

These are optional and subject to external community review.

- PrivacySpy: https://privacyspy.org/
- Privacy Guides: https://www.privacyguides.org/en/about/criteria/

Recommended path:

1. Wait until the privacy policy, security policy, release signing, and public website are stable.
2. Submit a concise description of the app's threat model:
   - local-first screenshot, annotation, and pinning;
   - no account, cloud sync, telemetry, advertising SDK, or analytics service;
   - network access limited to update checks and downloads;
   - Developer ID signing, Apple notarization, and Sparkle update signatures for public releases.
3. Be explicit about limits:
   - screenshots shared through other apps are controlled by the user and destination service;
   - hosting providers may process necessary access, security, and delivery logs;
   - community inclusion is not a formal legal privacy certification.

## Paid or Heavyweight Programs

Do not present the following as current PinboardShot trust signals unless the project explicitly enters those programs:

- TRUSTe / TrustArc privacy certification.
- BBB National Programs privacy certifications or Data Privacy Framework services.
- ISO 27701, SOC 2, ePrivacyseal, or ESRB Privacy Certified.
