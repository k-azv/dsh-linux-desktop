#!/usr/bin/env bash
set -euo pipefail
rpm=$(realpath "${1:?built RPM required}")
[[ -f "$rpm" && "$rpm" == *.rpm ]] || exit 1
: "${TARGET_TAG:?source release tag required}"
docker run --rm -i -e TARGET_TAG -v "$rpm:/tmp/desktop.rpm:ro" fedora:44 bash -se <<'FEDORA'
dnf install -y /tmp/desktop.rpm rpmdevtools findutils
package=$(rpm -qp --qf '%{NAME}' /tmp/desktop.rpm)
mapfile -t sandboxes < <(rpm -ql "$package" | grep '^/opt/.*/chrome-sandbox$')
[[ ${#sandboxes[@]} == 1 ]]
sandbox=${sandboxes[0]}
[[ $(stat -c '%u:%g:%a' "$sandbox") == '0:0:4755' ]]
root=$(dirname "$sandbox")
[[ -d "$root/resources" && -f "$root/resources/app.asar" ]]
cli=$(command -v dsh)
[[ -x "$cli" ]]
case "$(readlink -f "$cli")" in "$root"/*) ;; *) echo 'dsh must resolve inside /opt application' >&2; exit 1 ;; esac
dsh --version
# rpmdev-vercmp returns 12 when the left EVR is older, 11 when newer, 0 when equal.
for pair in '0.2.2~rc.4 0.2.2~rc.5' '0.2.2~rc.5 0.2.2'; do
  read -r older newer <<< "$pair"
  rc=0
  rpmdev-vercmp "$older" "$newer" || rc=$?
  [[ $rc == 12 ]]
done
# The built artifact itself must use RPM's prerelease ordering, not just the fixture examples.
expected=${TARGET_TAG#dsh-v}
expected=${expected/-rc./~rc.}
[[ $(rpm -qp --qf '%{VERSION}' /tmp/desktop.rpm) == "$expected" ]]
echo 'Fedora RPM layout, sandbox, CLI and version ordering passed'
FEDORA
