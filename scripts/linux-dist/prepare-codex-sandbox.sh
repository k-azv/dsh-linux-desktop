#!/usr/bin/env bash
set -euo pipefail

# Ubuntu 24.04 restricts capabilities inside unprivileged user namespaces via AppArmor,
# blocking bubblewrap loopback setup for Codex's workspace-write sandbox on hosted runners.
if [[ -r /proc/sys/kernel/apparmor_restrict_unprivileged_userns ]] \
  && [[ "$(cat /proc/sys/kernel/apparmor_restrict_unprivileged_userns)" != '0' ]]; then
  sudo -n sysctl -w kernel.apparmor_restrict_unprivileged_userns=0 \
    || echo 'apparmor userns knob unchanged — the functional probe decides' >&2
fi

echo 'Verifying Codex bwrap sandbox preflight...'
codex sandbox /bin/true
