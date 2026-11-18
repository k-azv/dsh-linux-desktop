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
import { createInterface } from 'node:readline'
const instruction = process.env.DSH_OWNER_INSTRUCTION
  ? readFileSync(process.env.DSH_OWNER_INSTRUCTION, 'utf8') : ''
const state = `${process.env.RUNNER_TEMP ?? '/tmp'}/dsh-codex`
const prompt = `Repair only the Linux downstream sync/build/smoke failure. First read apps/desktop/AGENTS.md
and .agents/notes/implemented/process/. If either is missing, request a decision rather than inventing policy.
Read the failure log at ${process.env.DSH_CODEX_LOG}. Preserve upstream ancestry and all Linux workflows.
Never modify .github/workflows, scripts/linux-dist, credentials, git remotes, or release state.
A draft sync checkpoint may contain conflict markers; resolve those using the owner instruction.
The sandbox mounts .git/index read-only: edit or remove conflicted files only, and do not run git add
or any other command that writes the index.
Do not commit, push, merge, open PRs, release, or use network services other than dependency fetching.
If a product or architectural choice needs the owner's decision, write ${process.env.DSH_DECISION_FILE}
with: ## Decision, ## Context, ## Options (at least two with tradeoffs), ## Recommendation.
Then exit successfully without guessing. Otherwise resolve conflicts and repair source only.
Owner decision (if present):\n${instruction}`
const args = ['exec', '--json', '--ephemeral', '--sandbox', 'workspace-write', '--add-dir', state,
  '-c', 'approval_policy="never"']
// OPENAI_BASE_URL selects an API-key provider instead of ChatGPT authentication.
if (process.env.OPENAI_BASE_URL) {
  args.push('-c', 'model_provider="linux_api"', '-c', 'model_providers.linux_api.name="Linux API"',
    '-c', `model_providers.linux_api.base_url=${JSON.stringify(process.env.OPENAI_BASE_URL)}`,
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
const timer = setTimeout(() => stop('Codex exceeded 15 minutes'), 15 * 60_000)
createInterface({ input: child.stdout }).on('line', line => {
  console.log(line)
  try {
    const e = JSON.parse(line)
    if (e.type === 'item.completed' && ['reasoning', 'agent_message'].includes(e.item?.type) && ++turns > 12)
      stop('Codex exceeded 12 reasoning/message turns')
    if (e.type === 'item.started' && ['command_execution', 'mcp_tool_call'].includes(e.item?.type) && ++tools > 40)
      stop('Codex exceeded 40 tool calls')
  } catch {}
})
child.on('error', e => { clearTimeout(timer); console.error(e); process.exitCode = 1 })
child.on('exit', code => { clearTimeout(timer); process.exitCode = stopped ? 124 : code ?? 1 })
child.stdin.end(prompt)
JS
