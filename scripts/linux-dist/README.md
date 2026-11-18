# Linux distribution automation

English | [中文](README.zh.md)

The `linux` branch preserves full upstream ancestry. Daily checks select the highest newer stable or `rc.N` GitHub Release named `dsh-vX.Y.Z`, and dispatch sync explicitly. Sync merges upstream tags into `sync/<tag>`, verifies the exact candidate in an unprivileged job, atomically merges that verified tree into `linux`, and releases the verified RPM, AppImage, and checksums as `<tag>-linux.1`. The sync-state update is part of that verified commit and reaches `linux` through the merge.

## Repository setup

After the initial reviewed push, set the repository default branch to `linux`; scheduled and issue-comment workflows are discovered on the default branch. Allow GitHub Actions to create and approve pull requests, and grant workflow tokens the declared write permissions. Enable merge commits. Set the `OPENAI_API_KEY` repository secret, and optionally `OPENAI_BASE_URL` for a Responses-compatible endpoint. When `OPENAI_BASE_URL` is set, bounded Codex defaults to `deepseek-v4.1-flash`; otherwise Codex uses its provider default unless `CODEX_MODEL` is set, with `CODEX_REASONING_EFFORT` defaulting to `max` (non-empty when set). Workflow commits use the downstream owner's configured Git identity.

## Desktop adapter interfaces

- `pnpm --dir apps/desktop run package linux-x64 --unsigned` must build an x64 RPM and AppImage under `apps/desktop/.desktop-build/targets/linux-x64/unsigned-artifacts/`
- `DSH_DESKTOP_TARGET_PLATFORM=linux` and `DSH_DESKTOP_TARGET_ARCH=x64` select Linux for `smoke-packaged-runtime.ts --unsigned`
- The AppImage's `AppRun` accepts `--linux-smoke-test` and `--user-data-dir`. When `DSH_LINUX_SMOKE_REPORT` is set in smoke mode, write JSON `{ "guiReady": true, "hostReady": true, "hostPid": 123 }` after a renderer has loaded and the authenticated Host has reported readiness. Keep both processes running until the test terminates them. The smoke script checks the reported Host PID is alive
- RPM installation puts the application under `/opt/`, installs root-owned mode `4755` `chrome-sandbox`, and exposes `dsh` on PATH resolving into the application tree. Its RPM Version maps `-rc.N` to `~rc.N`

The coordinator supplies these Desktop adaptations, `apps/desktop/AGENTS.md`, and the process notes before the initial push. The automation treats missing healing instructions as an owner decision.

## Dispatch and decisions

`target_tag` starts a new merge from `linux`. `verify_ref` selects an exact SHA; with `target_tag`, it must be the current head of `sync/<tag>`. Without `target_tag`, it verifies an exact commit without publishing. `dry_run` defaults to true and performs local sync/build verification. Publishing a previously pushed sync head requires `target_tag`, `verify_ref`, `dry_run=false`, and `release=true`. Same-repository `sync/*` pull requests run verification; explicit dispatch drives publication.

Infrastructure failures are classified before healing. Network/registry transport failures receive at most two retries; disk, authentication, and unknown failures stop. Merge conflicts, recognized build failures, and smoke failures can invoke Codex. Each Codex process is limited to 15 minutes, 12 reasoning/message completions, and 40 tool calls; build healing runs once. Healing cannot change automation files. Verification jobs have read-only repository permission and define no `GH_TOKEN`, `OPENAI_API_KEY`, or `OPENAI_BASE_URL`; write credentials belong only to preparation, healing, and publication.

An owner decision produces a Draft PR labeled `needs-decision`, with context, options, and a recommendation. A paused merge checkpoint may contain conflict markers; it remains blocked from publication until the owner replies `/decide <instruction>` and the exact resulting commit passes all verification. The owner-comment workflow reads the PR context, applies the instruction, and explicitly dispatches verification and release for its head SHA.

`force_resync=true` explicitly allows replacing the same `sync/<tag>` branch even when an open PR still tracks it; close or abandon that PR first. Daily checks skip dispatch while any open `sync/*` PR exists, and a normal sync refuses to overwrite an open PR for the same branch.
