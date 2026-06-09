# macOS AppleSystemPolicy GUI launch deny

Case notes for a macOS failure mode where newly installed apps appear to
"flash crash" from Finder, Dock, Spotlight, or `open`, but the app binary is not
actually crashing. The GUI launch path is denied by AppleSystemPolicy.

This repository is a public, sanitized incident write-up. It is not an
official Apple bug report and does not prove a single root cause.

Chinese version: [README.zh-CN.md](README.zh-CN.md)

中文摘要：这是一个公开、脱敏的 macOS 案例记录。现象是新安装应用从
Finder、Dock、Spotlight 或 `open` 启动时像“闪退”，但真实原因可能是
AppleSystemPolicy 在 GUI 启动链中拒绝进程，而不是应用自身崩溃。

Terminal-only repair guide:

- English: [MANUAL_TERMINAL_GUIDE.md](MANUAL_TERMINAL_GUIDE.md)
- 中文: [MANUAL_TERMINAL_GUIDE.zh-CN.md](MANUAL_TERMINAL_GUIDE.zh-CN.md)

## Symptom

- Many newly installed apps immediately quit when launched from the GUI.
- No normal crash report is written under `~/Library/Logs/DiagnosticReports`.
- Directly executing the app's main binary may work.
- `codesign`, `spctl --type execute`, or notarization checks may pass.

Example log line:

```text
AppleSystemPolicy: ASP: Security policy would not allow process: <pid>, /Applications/Antigravity.app/Contents/MacOS/Antigravity
```

## What This Means

This points to macOS launch/security policy, not necessarily to an app bug.

In the observed case:

- `/Applications/Antigravity.app` passed code-signing and notarization checks.
- Direct binary execution started the app.
- GUI launch through LaunchServices was killed by AppleSystemPolicy.
- Several app bundles carried `com.apple.provenance`, `com.apple.macl`, or
  `com.apple.quarantine` extended attributes.
- Gatekeeper assessment state was found disabled, then restored.
- Restarting policy/trust services plus clearing stale launch-source attributes
  resolved the GUI launch denial.

## Diagnostics

Check the current policy state:

```sh
spctl --status
```

Assess a specific app:

```sh
app="/Applications/Antigravity.app"
spctl --assess --type execute -vv "$app"
codesign --verify --deep --strict --verbose=2 "$app"
```

Watch launch policy logs while starting the app:

```sh
/usr/bin/log stream --style compact --timeout 20 \
  --predicate 'eventMessage CONTAINS[c] "Security policy would not allow process" OR eventMessage CONTAINS[c] "AppleSystemPolicy"'
```

Compare GUI launch with direct binary launch:

```sh
open -n /Applications/Antigravity.app
/Applications/Antigravity.app/Contents/MacOS/Antigravity
```

If direct execution works while GUI launch is denied, suspect LaunchServices,
Gatekeeper, provenance/quarantine state, or system policy caches.

## Repair Shape

The repair that worked in this case was:

1. Re-enable Gatekeeper assessment.
2. Remove stale launch-source extended attributes from app bundles.
3. Re-register LaunchServices.
4. Restart policy and trust evaluation services.
5. Validate with `open`, process checks, and fresh logs.

In one observed recurrence on 2026-06-09, Gatekeeper was already enabled and
the affected apps still assessed as notarized Developer ID apps. A user-level
refresh was enough: clear the same top-level app attributes, re-register
LaunchServices, and restart the current user's LaunchServices-related caches.
Try this lower-impact path before killing system policy services when
diagnostics already show `accepted`.

The helper scripts in `scripts/` encode this shape:

```sh
scripts/diagnose-launch-policy.sh "/Applications/Antigravity.app"
scripts/repair-launch-policy-cache.sh
scripts/repair-launch-policy-cache.sh --apply
```

The repair script is dry-run by default. Use `--apply` only after reading it.

For users who do not use an AI agent, follow the complete terminal guide:
[MANUAL_TERMINAL_GUIDE.md](MANUAL_TERMINAL_GUIDE.md).

## Apple Reporting

Apple does not generally use public GitHub issues for macOS system bugs. If this
is reproducible on a clean machine, file it through Feedback Assistant and attach:

- `sysdiagnose`
- exact macOS version and build
- affected app paths and bundle IDs
- `spctl`, `codesign`, and `log stream` evidence
- whether direct binary execution differs from GUI launch

## What Not To Conclude

- Do not assume every affected app is broken.
- Do not assume notarization failed if `spctl --type execute` says accepted.
- Do not paste passwords, tokens, or private logs into public reports.
- Do not delete `/var/db/SystemPolicyConfiguration` blindly.

## Observed Environment

- macOS 26.5.1, arm64
- Affected examples included Electron-style apps and iOS-wrapper apps
- Primary recovered sample: Antigravity

## Status

After repair, Antigravity launched through `open`, stayed running, spawned its
helper processes, and no new AppleSystemPolicy denial appeared in the validation
window.

On 2026-06-09 the same failure recurred. Recent logs showed
`ASP: Security policy would not allow process` for Codex while `spctl --status`
reported `assessments enabled`. After the user-level refresh, Antigravity,
Claude, and Codex launched through `open`, `spctl --assess --type execute`
reported `accepted`, and no fresh ASP denial appeared in the validation window.
Tracked in [issue #1](https://github.com/bozliu/macos-apple-systempolicy-launch-deny/issues/1).
