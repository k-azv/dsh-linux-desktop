# Agent Note: Unofficial Linux desktop downstream distribution and sandbox policy

Status: implemented

English | [中文](2026-11-18-linux-desktop-distribution.zh.md)

## Problem

Upstream DeepSeek Harness provides Linux binaries in `primary-runtime` and `@deepseek-ai/node-addon-system`, yet [desktop-build-paths](../../../../apps/desktop/scripts/desktop-build-paths.mjs), [package-target](../../../../apps/desktop/scripts/package-target.ts), and [electron-builder-config](../../../../apps/desktop/scripts/electron-builder-config.mjs) restrict desktop packaging to `darwin` and `win32`. Meanwhile, upstream `master` moves rapidly with 35 repository workflows, so a downstream Linux distribution needs a low-maintenance way to track stable and `rc` releases, produce installable Fedora RPM and AppImage artifacts, preserve Chromium sandbox security, and involve the owner only for real merge or architectural decisions.

## Decision

Maintain a standalone downstream repository whose default `linux` branch holds the full upstream source history anchored at `dsh-v*` stable and `rc` release tags, keeping Linux adaptations as ordinary commits scoped to [apps/desktop](../../../../apps/desktop/AGENTS.md) and isolated automation under [linux-dist](../../../../scripts/linux-dist/README.md). Daily checks inspect upstream GitHub Releases (excluding drafts and `alpha` tags) and dispatch [linux-sync-and-build](../../../../.github/workflows/linux-sync-and-build.yml) into a `sync/<tag>` branch using `git merge --no-commit --no-ff` while restoring the downstream `.github/workflows/` directory verbatim so upstream workflows never enter the repository.

Before invoking Codex (`@openai/codex`) for self-healing, [classify-failure](../../../../scripts/linux-dist/classify-failure.mjs) separates transient network/registry transport errors (retried up to twice) and disk/auth failures (aborted cleanly) from merge conflicts, build errors, and smoke failures. Codex runs bounded by wall time, turn count, and tool calls, cannot alter automation files, and pauses the PR as a `needs-decision` Draft PR whenever a change touches sandbox security, system RPM dependencies, feature removal, or files outside `apps/desktop/`. The repository owner resolves paused PRs via `/decide` comments in [linux-decide](../../../../.github/workflows/linux-decide.yml) or by pushing directly to `sync/<tag>`, and green PRs merge exclusively via true merge commits to preserve upstream common ancestors.

Packaged Linux builds target `linux-x64 --unsigned`, emit both `.rpm` and `.AppImage`, expose `/usr/bin/dsh` pointing into `/opt/DeepSeek Harness/resources/runtime/cli/bin/dsh`, map `-rc.N` to `~rc.N` in RPM headers for monotonic `dnf` upgrades, and retain Chromium's standard sandbox by shipping `chrome-sandbox` at root-owned mode `4755` without passing `--no-sandbox` to installed launchers. Automated verification chains upstream `smoke-packaged-runtime.ts`, headless `xvfb-run` GUI and authenticated Host readiness (`--linux-smoke-test`), and a Fedora container `dnf install` and `rpmdev-vercmp` check on the exact verified commit SHA before releasing the same verified artifacts.

## Consequences

- Clean release merges build, verify, and publish with zero LLM API spend, while failures provide normal source diffs and IDE-checkout PRs instead of patch-on-patch reviews.
- Retaining root-owned `4755` `chrome-sandbox` preserves renderer isolation on Fedora without `--no-sandbox`, while requiring `rpm` post-install setup and Fedora container validation on every release.
- Requiring true merge commits on `linux` keeps three-way merge ancestry intact across releases and forbids squash or rebase merges on `sync/*` PRs.
- Downstream policy stays localized to `apps/desktop/AGENTS.md` and dated notes under `.agents/notes/`, avoiding edits to root `AGENTS.md`.

## Alternatives considered

- **Separate patch-only control repository without source.** Keeping only `patches/*.patch` avoids storing upstream files in the repository, yet forces maintainers and reviewers to read diffs of diffs and reconstruct an upstream checkout manually whenever AI healing escalates.
- **GitHub Fork syncing `master` daily.** Tracking `master` drags downstream builds through unrelated daily churn and upstream workflow triggers, and GitHub Fork defaults risk opening PRs against the upstream repository.
- **Forcing `--no-sandbox` unconditionally in RPM launchers.** Disabling Chromium's sandbox avoids SUID permission checks on restrictive hosts, yet weakens renderer isolation even on Fedora systems where standard user namespaces and `4755` `chrome-sandbox` work cleanly.
