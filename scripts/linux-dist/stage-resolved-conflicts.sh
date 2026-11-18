#!/usr/bin/env bash
set -euo pipefail
: "${RUNNER_TEMP:?runner temporary directory required}"
protected_status=$(git status --porcelain --untracked-files=all -- .github/workflows scripts/linux-dist)
if [[ -n "$protected_status" ]]; then
  echo 'Protected automation paths changed during healing:' >&2
  printf '%s\n' "$protected_status" >&2
  exit 1
fi
if [[ -s "$RUNNER_TEMP/dsh-codex/needs-decision.md" ]]; then
  exit 0
fi
mapfile -d '' unmerged < <(git diff --name-only -z --diff-filter=U)
for path in "${unmerged[@]}"; do
  [[ -e "$path" ]] || continue
  if grep -nE '^(<<<<<<< |=======$|>>>>>>> )' -- "$path"; then
    echo "Conflict markers remain in $path" >&2
    exit 1
  fi
done
if (( ${#unmerged[@]} > 0 )); then
  git add -A -- "${unmerged[@]}"
fi
if [[ -n "$(git diff --name-only --diff-filter=U)" ]]; then
  echo 'Unmerged paths remain after staging resolved conflicts:' >&2
  git diff --name-only --diff-filter=U >&2
  exit 1
fi
