#!/usr/bin/env bash
set -euo pipefail
# Desktop Linux adapter writes this report only after renderer and authenticated Host readiness.
# Usage: xvfb-run -a scripts/linux-dist/xvfb-smoke.sh <linux-unpacked/executable>
app=$(realpath "${1:?packaged executable required}")
[[ -x "$app" && -n "${DISPLAY:-}" ]] || { echo 'Executable and X display required' >&2; exit 1; }
work=$(mktemp -d)
pid=
cleanup() {
  if [[ -n "$pid" ]]; then kill -- "-$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; fi
  cat "$work/app.log" 2>/dev/null || true
  rm -rf "$work"
}
trap cleanup EXIT
export XDG_CONFIG_HOME="$work/config" XDG_CACHE_HOME="$work/cache"
export DSH_LINUX_SMOKE_REPORT="$work/ready.json"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
# Extracted Electron runners cannot rely on an installed setuid sandbox; RPM checks cover it.
setsid dbus-run-session -- "$app" --no-sandbox --disable-gpu --linux-smoke-test --user-data-dir="$work/user-data" >"$work/app.log" 2>&1 &
pid=$!
for ((i=0; i<90; i++)); do
  kill -0 "$pid" 2>/dev/null || { echo 'GUI exited before readiness' >&2; exit 1; }
  if [[ -s "$DSH_LINUX_SMOKE_REPORT" ]]; then
    node --input-type=module - "$DSH_LINUX_SMOKE_REPORT" <<'JS'
import { readFileSync } from 'node:fs'
const r = JSON.parse(readFileSync(process.argv[2], 'utf8'))
if (r.guiReady !== true || r.hostReady !== true || !Number.isInteger(r.hostPid) || r.hostPid <= 1)
  throw new Error('Expected guiReady, hostReady, and live hostPid')
process.kill(r.hostPid, 0)
JS
    echo 'Packaged GUI and Host readiness passed'
    exit 0
  fi
  sleep 1
done
echo 'Timed out waiting for packaged GUI and Host readiness report' >&2
exit 1
