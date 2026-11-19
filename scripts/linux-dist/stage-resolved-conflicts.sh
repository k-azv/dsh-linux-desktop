#!/usr/bin/env bash
set -euo pipefail
: "${RUNNER_TEMP:?runner temporary directory required}"
mode=${DSH_CODEX_MODE:-}
case "$mode" in
  merge|verify|decide) ;;
  *)
    echo 'DSH_CODEX_MODE must be merge, verify, or decide' >&2
    exit 2
    ;;
esac
protected_status=$(git status --porcelain --untracked-files=all -- .github/workflows .github/dependabot.yml scripts/linux-dist)
if [[ -n "$protected_status" ]]; then
  echo 'Protected automation paths changed during healing:' >&2
  printf '%s\n' "$protected_status" >&2
  exit 1
fi
mapfile -d '' unmerged < <(git diff --name-only -z --diff-filter=U)
if [[ "$mode" == verify ]]; then
  mapfile -d '' status_entries < <(git status --porcelain -z --untracked-files=all)
  for ((i = 0; i < ${#status_entries[@]}; i++)); do
    entry=${status_entries[$i]}
    status=${entry:0:2}
    path=${entry:3}
    if [[ "$path" != apps/desktop/* ]]; then
      echo "Verification healing changed a path outside apps/desktop: $path" >&2
      exit 1
    fi
    if [[ "$status" == R* || "$status" == C* ]]; then
      i=$((i + 1))
      source_path=${status_entries[$i]:-}
      if [[ "$source_path" != apps/desktop/* ]]; then
        echo "Verification healing renamed a path outside apps/desktop: $source_path" >&2
        exit 1
      fi
    fi
  done
elif [[ "$mode" == merge ]]; then
  mapfile -d '' untracked < <(git ls-files -z --others --exclude-standard -- ':!apps/desktop/')
  if (( ${#untracked[@]} > 0 )); then
    echo 'Merge healing created untracked paths outside apps/desktop:' >&2
    printf '%s\n' "${untracked[@]}" >&2
    exit 1
  fi
  mapfile -d '' unstaged < <(git diff --name-only -z)
  for path in "${unstaged[@]}"; do
    [[ "$path" == apps/desktop/* ]] && continue
    is_unmerged=false
    for unmerged_path in "${unmerged[@]}"; do
      if [[ "$path" == "$unmerged_path" ]]; then
        is_unmerged=true
        break
      fi
    done
    if [[ "$is_unmerged" == false ]]; then
      echo "Merge healing modified a non-conflicted path outside apps/desktop: $path" >&2
      exit 1
    fi
  done
fi
if [[ -s "$RUNNER_TEMP/dsh-codex/needs-decision.md" ]]; then
  exit 0
fi
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
