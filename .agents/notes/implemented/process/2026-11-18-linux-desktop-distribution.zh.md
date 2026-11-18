# Agent Note: Unofficial Linux desktop downstream distribution and sandbox policy

Status: implemented

[English](2026-11-18-linux-desktop-distribution.md) | 中文

## Problem

上游 DeepSeek Harness 已在 `primary-runtime` 与 `@deepseek-ai/node-addon-system` 中提供 Linux 二进制，但 [desktop-build-paths](../../../../apps/desktop/scripts/desktop-build-paths.mjs)、[package-target](../../../../apps/desktop/scripts/package-target.ts) 和 [electron-builder-config](../../../../apps/desktop/scripts/electron-builder-config.mjs) 将桌面打包限制为 `darwin` 与 `win32`。同时上游 `master` 提交频率极高且包含 35 个仓库工作流，因此下游 Linux 发行版需要一种低维护成本的方式来跟随正式版与 `rc` 发布、产出可安装的 Fedora RPM 与 AppImage 产物、保留 Chromium 沙箱隔离，并仅在真正需要合并或架构拍板时才打扰仓库所有者。

## Decision

维护一个独立的下游源码仓库，以默认分支 `linux` 保存锚定在 `dsh-v*` 正式版与 `rc` 发布 Tag 上的完整上游历史，并将 Linux 适配以普通提交保存在 [apps/desktop](../../../../apps/desktop/AGENTS.md) 以及独立脚本目录 [linux-dist](../../../../scripts/linux-dist/README.zh.md) 中。每日检查筛选上游 GitHub Releases（排除草稿与 `alpha` 标签），并通过 [linux-sync-and-build](../../../../.github/workflows/linux-sync-and-build.yml) 拉出 `sync/<tag>` 分支执行 `git merge --no-commit --no-ff`，同时将 `.github/workflows/` 原样恢复为下游自有版本，确保上游工作流永不进入仓库。

在唤醒 Codex（`@openai/codex`）执行自愈前，[classify-failure](../../../../scripts/linux-dist/classify-failure.mjs) 先区分瞬时网络/源传输错误（最多重试两次）、磁盘或鉴权失败（直接中止），以及合并冲突、构建错误与冒烟失败。Codex 在耗时、轮次与工具调用上限内运行，禁止修改自动化脚本，并在改动涉及沙箱安全、系统级 RPM 依赖、功能裁剪或越出 `apps/desktop/` 范围时暂停流程并挂出带 `needs-decision` 标签的 Draft PR。仓库所有者可通过 [linux-decide](../../../../.github/workflows/linux-decide.yml) 中的 `/decide` 评论或直接推送 `sync/<tag>` 分支完成处理，且所有同步 PR 必须使用保留双父节点的合并提交合入 `linux` 分支。

Linux 打包统一采用 `linux-x64 --unsigned`，同时产出 `.rpm` 与 `.AppImage`，将 `/usr/bin/dsh` 链接到 `/opt/DeepSeek Harness/resources/runtime/cli/bin/dsh`，在 RPM 元数据中将 `-rc.N` 映射为 `~rc.N` 以保证 `dnf` 单调升级，并通过以 root 属主 `4755` 权限安装 `chrome-sandbox` 保留 Chromium 标准沙箱（禁止在安装版启动器中使用 `--no-sandbox`）。自动化验证将上游 `smoke-packaged-runtime.ts`、`xvfb-run` 无头 GUI 与已鉴权 Host 就绪检查（`--linux-smoke-test`），以及 Fedora 容器内的 `dnf install` 与 `rpmdev-vercmp` 校验串联在同一精确提交 SHA 上，通过后直接发布同一批已验证产物。

## Consequences

- 无冲突的常规版本同步可实现零 LLM API 费用自动构建、验证并发布，需要人工介入时直接提供完整源码 Diff 与本地 IDE 检出分支，不再面对补丁套补丁的审查。
- 保留 root 属主 `4755` 权限的 `chrome-sandbox` 可在 Fedora 上维持与官方一致的渲染进程隔离，同时要求每次发布都验证 RPM 安装后权限与容器安装结果。
- 强制要求在 `linux` 分支上保留真实合并提交以维持三方合并共同祖先，同步 PR 禁止使用 Squash 或 Rebase 合并。
- 下游策略收敛在 `apps/desktop/AGENTS.md` 与 `.agents/notes/` 独立日期文件中，无需修改根目录 `AGENTS.md`。

## Alternatives considered

- **无源码控制仓加补丁文件集合。** 仅保存 `patches/*.patch` 虽可避免仓库存源码，但每次需要人工介入时审查的是补丁的补丁，且必须手动组装上游源码重放才能修改。
- **通过 GitHub Fork 每日合并 `master`。** 跟踪 `master` 会卷入海量无关提交与上游工作流触发噪音，且 GitHub Fork 的默认 PR 目标容易误指向官方仓库。
- **在 RPM 启动器中无条件强制启用 `--no-sandbox`。** 关闭 Chromium 沙箱虽可绕开权限检查，但会削弱渲染进程隔离，而在默认开启用户命名空间且具备 `4755` `chrome-sandbox` 的 Fedora 上标准沙箱可正常运作。
