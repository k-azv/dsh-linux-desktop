#!/usr/bin/env bash
set -euo pipefail
: "${RUNNER_TEMP:?runner temporary directory required}"
: "${TARGET_TAG:?source tag required}"
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
output=apps/desktop/.desktop-build/targets/linux-x64/unsigned-artifacts
stage() {
  printf '%s\n' "$1" > "$RUNNER_TEMP/linux-failure-stage"
  : > "$RUNNER_TEMP/linux-stage.log"
}
run_stage() {
  local name=$1
  shift
  stage "$name"
  "$@" 2>&1 | tee -a "$RUNNER_TEMP/linux-stage.log"
}
install_stage() { pnpm install --frozen-lockfile; }
build_stage() {
  rm -rf "$output" "$RUNNER_TEMP/linux-release"
  pnpm --dir apps/desktop run package linux-x64 --unsigned
}
extracted=
cleanup() { if [[ -n "$extracted" ]]; then rm -rf "$extracted"; fi; }
smoke_stage() {
  pnpm --dir apps/desktop exec tsx scripts/smoke-packaged-runtime.ts --unsigned
  mapfile -d '' -t rpms < <(find "$output" -maxdepth 1 -name '*.rpm' -type f -print0)
  mapfile -d '' -t images < <(find "$output" -maxdepth 1 -name '*.AppImage' -type f -print0)
  [[ ${#rpms[@]} == 1 && ${#images[@]} == 1 ]] || { echo 'Expected exactly one RPM and one AppImage' >&2; exit 1; }
  # Test the actual AppImage payload, not only the sibling unpacked build directory.
  image=$(realpath "${images[0]}")
  extracted=$(mktemp -d)
  trap cleanup EXIT
  (cd "$extracted" && chmod +x "$image" && "$image" --appimage-extract >/dev/null)
  xvfb-run -a "$script_dir/xvfb-smoke.sh" "$extracted/squashfs-root/AppRun"
  "$script_dir/verify-rpm-fedora.sh" "${rpms[0]}"
  mkdir -p "$RUNNER_TEMP/linux-release"
  cp -- "${rpms[0]}" "${images[0]}" "$RUNNER_TEMP/linux-release/"
  (cd "$RUNNER_TEMP/linux-release" && sha256sum -- *.rpm *.AppImage > SHA256SUMS.txt)
}
run_stage install install_stage
run_stage build build_stage
run_stage smoke smoke_stage
