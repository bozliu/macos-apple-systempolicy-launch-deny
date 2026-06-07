#!/usr/bin/env bash
set -euo pipefail

apply=0

if [[ "${1:-}" == "--apply" ]]; then
  apply=1
elif [[ "${1:-}" != "" ]]; then
  echo "usage: $0 [--apply]" >&2
  exit 2
fi

run() {
  if [[ "$apply" == 1 ]]; then
    "$@"
  else
    printf 'DRY-RUN:'
    printf ' %q' "$@"
    printf '\n'
  fi
}

echo "This script repairs a suspected LaunchServices/Gatekeeper policy-cache issue."
echo "Default mode is dry-run. Re-run with --apply to make changes."
echo

echo "== clear launch-source extended attributes from app bundles =="
find /Applications "$HOME/Applications" -maxdepth 1 -name '*.app' -print 2>/dev/null | while IFS= read -r app; do
  echo "$app"
  for attr in com.apple.quarantine com.apple.provenance com.apple.macl; do
    if xattr -p "$attr" "$app" >/dev/null 2>&1; then
      run xattr -dr "$attr" "$app"
    fi
  done
done
echo

echo "== re-register LaunchServices =="
lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
run "$lsregister" -r -domain local -domain system -domain user
echo

echo "== re-enable Gatekeeper and restart policy/trust services =="
run sudo /usr/sbin/spctl --master-enable
run sudo /usr/bin/killall syspolicyd || true
run sudo /usr/bin/killall com.apple.CodeSigningHelper || true
run sudo /usr/bin/killall trustd || true
run sudo /usr/bin/killall trustevaluationagent || true
run sudo /usr/bin/killall amfid || true
echo

echo "== validate =="
run spctl --status

cat <<'EOF'

After applying:
1. Launch an affected app with open -n /Applications/Your.app
2. Check pgrep -afil 'YourAppName'
3. Watch for new AppleSystemPolicy denials:

/usr/bin/log show --last 2m --style compact \
  --predicate 'eventMessage CONTAINS[c] "Security policy would not allow process"'
EOF
