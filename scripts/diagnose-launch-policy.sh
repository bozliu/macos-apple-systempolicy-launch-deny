#!/usr/bin/env bash
set -euo pipefail

app="${1:-}"

if [[ -z "$app" ]]; then
  echo "usage: $0 /Applications/Some.app" >&2
  exit 2
fi

if [[ ! -e "$app" ]]; then
  echo "not found: $app" >&2
  exit 1
fi

echo "== system =="
sw_vers || true
uname -m || true
echo

echo "== gatekeeper =="
spctl --status 2>&1 || true
echo

echo "== bundle =="
echo "path: $app"
if [[ -f "$app/Contents/Info.plist" ]]; then
  /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Contents/Info.plist" 2>/dev/null || true
else
  echo "no Contents/Info.plist; this may be an iOS wrapper app or nonstandard bundle"
fi
echo

echo "== assessment =="
spctl --assess --type execute -vv "$app" 2>&1 || true
spctl --assess --type open -vv "$app" 2>&1 || true
codesign --verify --deep --strict --verbose=2 "$app" 2>&1 || true
echo

echo "== extended attributes =="
xattr -l "$app" 2>/dev/null || true
echo

echo "== recent policy denials =="
/usr/bin/log show --last 5m --style compact \
  --predicate 'eventMessage CONTAINS[c] "Security policy would not allow process" OR eventMessage CONTAINS[c] "AppleSystemPolicy"' \
  2>/dev/null | tail -120 || true

cat <<'EOF'

Tip:
Run this in another terminal while launching the app:

/usr/bin/log stream --style compact --timeout 20 \
  --predicate 'eventMessage CONTAINS[c] "Security policy would not allow process" OR eventMessage CONTAINS[c] "AppleSystemPolicy"'
EOF
