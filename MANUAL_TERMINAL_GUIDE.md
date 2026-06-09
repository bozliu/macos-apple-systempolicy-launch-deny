# Manual Terminal Guide

This guide is for users who do not have an AI agent. You can do the diagnosis
and repair yourself in Terminal.

Use this when apps launch from Finder, Dock, Spotlight, or `open`, then
immediately quit, and logs show AppleSystemPolicy denial.

## Before You Start

- You need an administrator account.
- `sudo` may ask for your Mac password. Type it in Terminal; it will not be
  shown on screen.
- Do not paste passwords, tokens, or private logs into public issues.
- Start with one affected app. Replace the example path with your app path.
- The copy-paste commands below work in macOS Terminal's default `zsh`.

```sh
APP="/Applications/Antigravity.app"
```

## Step 1: Confirm The Symptom

Run:

```sh
APP="/Applications/Antigravity.app"
open -n "$APP"
sleep 8
pgrep -afil "$(basename "$APP" .app)" || true
```

If no process remains, the app may have been denied or crashed.

Now watch the security policy log while launching the app again:

```sh
/usr/bin/log stream --style compact --timeout 30 \
  --predicate 'eventMessage CONTAINS[c] "Security policy would not allow process" OR eventMessage CONTAINS[c] "AppleSystemPolicy"'
```

In another Terminal window, launch the app:

```sh
open -n "$APP"
```

If you see a line like this, this guide is relevant:

```text
ASP: Security policy would not allow process: <pid>, /Applications/Your.app/Contents/MacOS/YourApp
```

## Step 2: Check Signing And Gatekeeper

Run:

```sh
spctl --status
spctl --assess --type execute -vv "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
xattr -l "$APP" 2>/dev/null || true
```

Notes:

- `spctl --type execute` may say `accepted` even when GUI launch is still
  denied.
- `spctl --type open` may say `rejected` with `Insufficient Context` for some
  apps; by itself, that is not proof the app is broken.
- If direct binary execution works but GUI launch fails, suspect the macOS
  launch policy path:

```sh
"$APP/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist")"
```

Press `Control-C` to stop it if it starts successfully.

## Step 3: For Recurrences, Try The User-Level Refresh First

If this exact problem came back and `spctl --status` already says
`assessments enabled`, try this lower-impact refresh first. It does not use
`sudo`, does not delete apps, and only removes three launch-source attributes
from top-level app bundles.

```sh
for root in /Applications "$HOME/Applications"; do
  [ -d "$root" ] || continue
  find "$root" -maxdepth 1 -name '*.app' -print 2>/dev/null |
  while IFS= read -r app; do
    echo "$app"
    for attr in com.apple.quarantine com.apple.provenance com.apple.macl; do
      xattr -dr "$attr" "$app" 2>/dev/null || true
    done
  done
done

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -r -domain local -domain system -domain user

killall -u "$USER" cfprefsd sharedfilelistd 2>/dev/null || true
spctl --status
```

Then skip to the validation step. If affected apps still fail, continue with the
administrator repair below.

## Step 4: Try A Targeted Repair

This clears stale launch-source attributes only from the affected app and
re-registers LaunchServices.

```sh
APP="/Applications/Antigravity.app"

sudo /usr/sbin/spctl --master-enable

for attr in com.apple.quarantine com.apple.provenance com.apple.macl; do
  sudo xattr -dr "$attr" "$APP" 2>/dev/null || true
done

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -r -domain local -domain system -domain user

killall -u "$USER" cfprefsd sharedfilelistd 2>/dev/null || true
```

Restart policy and trust evaluation services. macOS launchd should start them
again automatically:

```sh
sudo killall syspolicyd 2>/dev/null || true
sudo killall com.apple.CodeSigningHelper 2>/dev/null || true
sudo killall trustd 2>/dev/null || true
sudo killall trustevaluationagent 2>/dev/null || true
sudo killall amfid 2>/dev/null || true

sleep 2
spctl --status
```

## Step 5: If Many Apps Are Affected

If multiple newly installed apps fail the same way, clear the same attributes
from top-level app bundles in `/Applications` and `~/Applications`.

Read this command first. It removes only these extended attributes:
`com.apple.quarantine`, `com.apple.provenance`, and `com.apple.macl`.

```sh
find /Applications "$HOME/Applications" -maxdepth 1 -name '*.app' -print 2>/dev/null |
while IFS= read -r app; do
  echo "$app"
  for attr in com.apple.quarantine com.apple.provenance com.apple.macl; do
    sudo xattr -dr "$attr" "$app" 2>/dev/null || true
  done
done

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -r -domain local -domain system -domain user

sudo /usr/sbin/spctl --master-enable
sudo killall syspolicyd 2>/dev/null || true
sudo killall com.apple.CodeSigningHelper 2>/dev/null || true
sudo killall trustd 2>/dev/null || true
sudo killall trustevaluationagent 2>/dev/null || true
sudo killall amfid 2>/dev/null || true
```

## Step 6: Validate

Launch the affected app again:

```sh
APP="/Applications/Antigravity.app"
open -n "$APP"
sleep 8
pgrep -afil "$(basename "$APP" .app)" || true
```

Check for fresh denials:

```sh
/usr/bin/log show --last 2m --style compact \
  --predicate 'eventMessage CONTAINS[c] "Security policy would not allow process"' |
tail -80
```

Success looks like this:

- the app process remains running,
- helper processes may appear,
- no fresh `Security policy would not allow process` line appears for that app.

## Helper Script Option

If you prefer using the scripts in this repository:

```sh
git clone https://github.com/bozliu/macos-apple-systempolicy-launch-deny.git
cd macos-apple-systempolicy-launch-deny

scripts/diagnose-launch-policy.sh "/Applications/Antigravity.app"
scripts/repair-launch-policy-cache.sh
scripts/repair-launch-policy-cache.sh --apply
```

The repair script is dry-run by default. The `--apply` run is the one that makes
changes.

## If It Still Fails

Try one reboot, then run the validation step again.

If it still fails:

- do not delete `/var/db/SystemPolicyConfiguration` blindly,
- collect exact app path, bundle ID, macOS version, and log lines,
- run `sudo sysdiagnose`,
- file a report with Apple through Feedback Assistant.

Apple does not usually handle macOS system bugs through public GitHub issues.
