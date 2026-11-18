#!/usr/bin/env bash
set -euo pipefail
: "${RUNNER_TEMP:?runner temporary directory required}"
: "${TARGET_TAG:?source tag required}"
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
stage() { printf '%s\n' "$1" > "$RUNNER_TEMP/linux-failure-stage"; }
stage install
pnpm install --frozen-lockfile
stage build
output=apps/desktop/.desktop-build/targets/linux-x64/unsigned-artifacts
rm -rf "$output" "$RUNNER_TEMP/linux-release"
pnpm --dir apps/desktop run package linux-x64 --unsigned
stage smoke
pnpm --dir apps/desktop exec tsx scripts/smoke-packaged-runtime.ts --unsigned
mapfile -d '' -t rpms < <(find "$output" -maxdepth 1 -name '*.rpm' -type f -print0)
mapfile -d '' -t images < <(find "$output" -maxdepth 1 -name '*.AppImage' -type f -print0)
[[ ${#rpms[@]} == 1 && ${#images[@]} == 1 ]] || { echo 'Expected exactly one RPM and one AppImage' >&2; exit 1; }
# Test the actual AppImage payload, not only the sibling unpacked build directory.
image=$(realpath "${images[0]}")
extracted=$(mktemp -d)
trap 'rm -rf "$extracted"' EXIT
(cd "$extracted" && chmod +x "$image" && "$image" --appimage-extract >/dev/null)
xvfb-run -a "$script_dir/xvfb-smoke.sh" "$extracted/squashfs-root/AppRun"
"$script_dir/verify-rpm-fedora.sh" "${rpms[0]}"
mkdir -p "$RUNNER_TEMP/linux-release"
cp -- "${rpms[0]}" "${images[0]}" "$RUNNER_TEMP/linux-release/"
(cd "$RUNNER_TEMP/linux-release" && sha256sum -- *.rpm *.AppImage > SHA256SUMS.txt)
