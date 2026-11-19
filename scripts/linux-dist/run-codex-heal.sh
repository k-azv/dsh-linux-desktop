#!/usr/bin/env bash
set -euo pipefail
# Usage: run-codex-heal.sh <failure-log> [owner-instruction-file]
: "${OPENAI_API_KEY:?OPENAI_API_KEY is required}"
export CODEX_API_KEY="$OPENAI_API_KEY"
log=$(realpath "${1:?failure log required}")
instruction=${2:-}
state=${RUNNER_TEMP:-/tmp}/dsh-codex
mkdir -p "$state"
rm -f "$state/needs-decision.md"
export DSH_DECISION_FILE="$state/needs-decision.md"
export DSH_CODEX_LOG="$log"
export DSH_OWNER_INSTRUCTION="$instruction"
# The CLI has no portable max-turns flag. Bound its JSON event stream as well as wall time.
node --input-type=module <<'JS'
import { spawn } from 'node:child_process'
import { readFileSync } from 'node:fs'
import { basename } from 'node:path'
import { createInterface } from 'node:readline'
const instruction = process.env.DSH_OWNER_INSTRUCTION
  ? readFileSync(process.env.DSH_OWNER_INSTRUCTION, 'utf8') : ''
const state = `${process.env.RUNNER_TEMP ?? '/tmp'}/dsh-codex`
const baseUrl = process.env.OPENAI_BASE_URL?.trim()
const configuredModel = process.env.CODEX_MODEL?.trim()
if (process.env.CODEX_MODEL !== undefined && !configuredModel) {
  console.error('CODEX_MODEL must be non-empty when set')
  process.exit(2)
}
const model = configuredModel ?? (baseUrl ? 'deepseek-v4.1-flash' : undefined)
const reasoningEffort = (process.env.CODEX_REASONING_EFFORT ?? 'max').trim()
if (!reasoningEffort) {
  console.error('CODEX_REASONING_EFFORT must be non-empty')
  process.exit(2)
}
const fallbackMode = instruction ? 'decide'
  : basename(process.env.DSH_CODEX_LOG ?? '') === 'linux-merge.log' ? 'merge' : 'verify'
const mode = (process.env.DSH_CODEX_MODE ?? fallbackMode).trim()
if (!['merge', 'verify', 'decide'].includes(mode)) {
  console.error(`Unsupported DSH_CODEX_MODE: ${mode}`)
  process.exit(2)
}
const stageInstruction = mode === 'merge'
  ? `You are in the prepare merge-conflict step. Resolve ONLY the conflicted files; edit or remove
conflicted files only. Verify their syntax or JSON validity, confirm no conflict markers remain,
and exit immediately.
Do NOT run pnpm install, full packaging (package linux-x64), or smoke/RPM suites:
verify_initial runs the full verification immediately after prepare.`
  : mode === 'decide'
    ? `You are applying an owner /decide instruction. A draft sync checkpoint may contain committed
conflict markers; resolve all conflict markers and apply the owner instruction, verify syntax/JSON
validity and that no conflict markers remain; edit or remove only the files required for the repair.
Do NOT run full packaging or smoke/RPM suites because the workflow runs verification after this step.`
    : `You are healing a verified build or smoke failure. Make minimal source repairs under
apps/desktop/; edit or remove only the files required for the repair, and run only focused local
checks rather than duplicating the full verify_healed pipeline.`
const prompt = `Repair only the Linux downstream sync/build/smoke failure. First read apps/desktop/AGENTS.md
and .agents/notes/implemented/process/2026-11-18-linux-desktop-distribution.md. If either is missing,
request a decision rather than inventing policy.
Read the failure log at ${process.env.DSH_CODEX_LOG}. Preserve upstream ancestry and all Linux workflows.
Never modify .github/workflows, .github/dependabot.yml, scripts/linux-dist, credentials, git remotes, or release state.
${stageInstruction}
The sandbox mounts .git/index read-only, so do not run git add or any other command that writes the index.
Do not commit, push, merge, open PRs, release, or use network services other than dependency fetching.
If a product or architectural choice needs the owner's decision, write ${process.env.DSH_DECISION_FILE}
with: ## Decision, ## Context, ## Options (at least two with tradeoffs), ## Recommendation.
Then exit successfully without guessing. Otherwise resolve the conflicts or repair source within
those job boundaries.
Owner decision (if present):\n${instruction}`
const args = ['exec', '--json', '--ephemeral', '--sandbox', 'workspace-write', '--add-dir', state,
  '-c', 'approval_policy="never"',
  ...(model === undefined ? [] : ['-m', model]),
  '-c', `model_reasoning_effort=${JSON.stringify(reasoningEffort)}`]
// OPENAI_BASE_URL selects an API-key provider instead of ChatGPT authentication.
if (baseUrl) {
  args.push('-c', 'model_provider="linux_api"', '-c', 'model_providers.linux_api.name="Linux API"',
    '-c', `model_providers.linux_api.base_url=${JSON.stringify(baseUrl)}`,
    '-c', 'model_providers.linux_api.env_key="OPENAI_API_KEY"', '-c', 'model_providers.linux_api.wire_api="responses"')
}
args.push('-')
const child = spawn('codex', args, { stdio: ['pipe', 'pipe', 'inherit'], detached: true })
let turns = 0, tools = 0, stopped = false
function stop(reason) {
  stopped = true
  console.error(reason)
  try { process.kill(-child.pid, 'SIGTERM') } catch {}
  setTimeout(() => { try { process.kill(-child.pid, 'SIGKILL') } catch {} }, 3000).unref()
}
const timer = setTimeout(() => stop('Codex exceeded 40 minutes'), 40 * 60_000)
createInterface({ input: child.stdout }).on('line', line => {
  console.log(line)
  try {
    const e = JSON.parse(line)
    if (e.type === 'item.completed' && ['reasoning', 'agent_message'].includes(e.item?.type) && ++turns > 1000)
      stop('Codex exceeded 1000 reasoning/message turns')
    if (e.type === 'item.started' && ['command_execution', 'mcp_tool_call'].includes(e.item?.type) && ++tools > 1000)
      stop('Codex exceeded 1000 tool calls')
  } catch {}
})
child.on('error', e => { clearTimeout(timer); console.error(e); process.exitCode = 1 })
child.on('exit', code => { clearTimeout(timer); process.exitCode = stopped ? 124 : code ?? 1 })
child.stdin.end(prompt)
JS
