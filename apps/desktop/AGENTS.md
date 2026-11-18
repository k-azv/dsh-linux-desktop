# AGENTS.md

This directory builds the unofficial Linux x64 downstream distribution of DeepSeek Harness Desktop alongside the upstream macOS and Windows targets. Follow [linux distribution note](../../.agents/notes/implemented/process/2026-11-18-linux-desktop-distribution.md) and [linux-dist README](../../scripts/linux-dist/README.md).

## Ownership and merge boundaries

- Keep downstream changes scoped to `apps/desktop/` and the isolated `scripts/linux-dist/` and `.github/workflows/linux-*.yml` files. Never touch `packages/` business logic or root `AGENTS.md` to fix a Desktop build or runtime issue without owner approval.
- Preserve upstream merge ancestry on `linux` by merging `sync/<tag>` PRs with true merge commits, never squash or rebase.
- During upstream merges, keep `.github/workflows/` at the downstream `linux` tree so upstream workflows never execute in this repository.

## Linux packaging and sandbox policy

- Linux packages are unsigned (`linux-x64 --unsigned`) and emit both `.rpm` and `.AppImage` artifacts under `apps/desktop/.desktop-build/targets/linux-x64/unsigned-artifacts/`.
- Linux ships the `dsh` runtime outside `app.asar` under `resources/dsh` (mapping both `dsh` and `dsh/node_modules` explicitly in `extraResources`) and validates `resources/dsh` integrity during `smoke-packaged-runtime.ts`.
- Retain Chromium's standard sandbox in installed RPM packages by shipping `/opt/DeepSeek Harness/chrome-sandbox` at root-owned mode `4755`; never add `--no-sandbox` to installed launchers or RPM post-install scripts without an explicit `/decide` instruction from the owner.
- Pre-release `-rc.N` tags map to `~rc.N` in RPM `Version` headers so `dnf` upgrades monotonically through `rc.N` to stable releases.

## Healing escalation rules

- Do not alter verification gates (`smoke-packaged-runtime.ts`, `xvfb-smoke.sh`, `verify-rpm-fedora.sh`) or skip RPM/sandbox checks when healing a build failure.
- Pause and request an owner decision via `needs-decision` whenever a fix requires relaxing sandbox security, dropping a user-facing Desktop capability, adding system RPM dependencies, or editing files outside `apps/desktop/`.
