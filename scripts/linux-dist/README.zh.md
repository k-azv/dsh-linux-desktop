# Linux distribution automation

[English](README.md) | 中文

`linux` 分支保留完整的上游提交祖先。每日检查会筛选最新的稳定版或 `rc.N` 上游 GitHub Release（命名为 `dsh-vX.Y.Z`），并显式触发同步。同步流程会将上游 Tag 合并到 `sync/<tag>` 分支、在无写入权限的作业中验证精确候选提交、将该已验证树原子合入 `linux`，并以 `<tag>-linux.1` 发布已验证的 RPM、AppImage 与校验和文件。同步状态更新包含在该已验证提交中，随合并进入 `linux` 分支。

## Repository setup

首次评审并推送后，需将仓库默认分支设为 `linux`；定时检查与 `issue_comment` 工作流均在默认分支上触发。同时需在仓库设置中允许 GitHub Actions 创建和批准 PR、授予工作流令牌声明的写入权限、启用合并提交，并配置 `OPENAI_API_KEY` 仓库密钥（如需使用兼容 Responses 接口的自定义端点，可额外配置 `OPENAI_BASE_URL`）。工作流提交使用下游仓库所有者的 Git 身份。

## Desktop adapter interfaces

- `pnpm --dir apps/desktop run package linux-x64 --unsigned` 必须在 `apps/desktop/.desktop-build/targets/linux-x64/unsigned-artifacts/` 下产出 x64 RPM 与 AppImage
- `DSH_DESKTOP_TARGET_PLATFORM=linux` 与 `DSH_DESKTOP_TARGET_ARCH=x64` 为 `smoke-packaged-runtime.ts --unsigned` 选择 Linux 目标
- AppImage 的 `AppRun` 需接受 `--linux-smoke-test` 与 `--user-data-dir`。在冒烟模式下若设置了 `DSH_LINUX_SMOKE_REPORT`，需在渲染进程加载完成且已鉴权的 Host 报告就绪后写入 JSON `{ "guiReady": true, "hostReady": true, "hostPid": 123 }`，并保持两个进程运行直至测试结束。冒烟脚本会检查所报告的 Host PID 是否存活
- RPM 安装时将应用部署到 `/opt/`、以 root 属主 `4755` 权限安装 `chrome-sandbox`，并在 PATH 中暴露指向应用目录内的 `dsh` 命令。其 RPM `Version` 字段将 `-rc.N` 映射为 `~rc.N`

协调者需在首次推送前提供上述桌面端适配、`apps/desktop/AGENTS.md` 以及本流程的 Agent Note。若缺少自愈指令文档，自动化流程会将其视为需要所有者决策。

## Dispatch and decisions

`target_tag` 会基于 `linux` 启动一次新的合并。`verify_ref` 指定精确的 40 位提交 SHA；若同时提供 `target_tag`，该 SHA 必须是 `sync/<tag>` 的当前顶端提交。未提供 `target_tag` 时，仅校验指定提交而不发布。`dry_run` 默认为 `true`，仅执行本地同步与构建验证。发布已推送的同步顶端提交时需提供 `target_tag`、`verify_ref`、`dry_run=false` 与 `release=true`。同仓库 `sync/*` PR 会触发验证；显式 dispatch 负责驱动发布。

在自愈前会先对基础设施故障进行分类。网络或依赖源传输错误最多重试两次；磁盘空间、鉴权与未知故障直接中止。合并冲突、已识别的构建失败以及冒烟失败可调用 Codex。每次 Codex 进程均受 15 分钟耗时、12 次推理/消息完成与 40 次工具调用上限约束；构建自愈最多运行一次。自愈过程中禁止修改自动化脚本文件。验证作业只有只读仓库权限，且不定义 `GH_TOKEN`、`OPENAI_API_KEY` 或 `OPENAI_BASE_URL`；写入凭据仅属于准备、自愈与发布作业。

需要所有者决策时会生成带 `needs-decision` 标签的 Draft PR，并附带背景、备选方案与推荐项。暂停的合并检查点允许保留冲突标记，在所有者回复 `/decide <instruction>` 且产生的新提交通过全部验证前均禁止进入发布。所有者评论工作流会读取 PR 上下文、应用指令并显式触发该顶端 SHA 的验证与发布。

`force_resync=true` 允许在仍存在打开的 PR 时显式替换同一 `sync/<tag>` 分支，使用前应先关闭或放弃该 PR。存在任意打开的 `sync/*` PR 时，每日检查会跳过触发；普通同步也会拒绝覆盖同一分支上仍打开的 PR。
