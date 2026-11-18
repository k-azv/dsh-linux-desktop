#!/usr/bin/env node
import { readFileSync, appendFileSync } from 'node:fs'
import { execFileSync } from 'node:child_process'

export function classifyFailure(log, stage, conflicts = false) {
  // Infrastructure takes priority: an AI edit cannot fix a full disk or registry outage.
  if (/ENOSPC|no space left on device|disk quota exceeded/i.test(log)) return { category: 'disk', action: 'abort' }
  if (/ERR_PNPM_FETCH_40[134]|401 Unauthorized|403 Forbidden|404 Not Found|authentication failed/i.test(log))
    return { category: 'registry-auth', action: 'abort' }
  if (/EAI_AGAIN|ECONNRESET|ETIMEDOUT|ENETUNREACH|ERR_PNPM_(?:FETCH|META_FETCH)|HTTP(?:Error)?[^\n]*(?:429|50[0234])|response[^\n]*(?:429|50[0234])|Could not resolve host|TLS handshake|Curl error \((?:5|6|7|28|35|56)\)|(?<![a-z0-9./_-])toomanyrequests(?![a-z0-9./_-])|too many requests|failed to download metadata|cannot download repomd|network timeout|connection timed out|temporary failure in name resolution|unexpected EOF/i.test(log))
    return { category: 'network-registry', action: 'retry' }
  if (conflicts) return { category: 'merge-conflict', action: 'heal' }
  if (stage === 'smoke') return { category: 'smoke', action: 'heal' }
  if (stage === 'build' && /error TS\d+|TS\d{4}:|ERR_PNPM_RECURSIVE_RUN_FIRST_FAIL|ELIFECYCLE|Build failed|build error|failed to (?:build|compile|package)|unsupported.*linux|unknown.*linux/i.test(log))
    return { category: 'typescript-build', action: 'heal' }
  return { category: 'unclassified', action: 'abort' }
}
if (process.argv[1] && import.meta.url === new URL(process.argv[1], 'file:').href) {
  const [file, stage] = process.argv.slice(2)
  const conflicts = execFileSync('git', ['diff', '--name-only', '--diff-filter=U'], { encoding: 'utf8' }).trim() !== ''
  const result = classifyFailure(readFileSync(file, 'utf8'), stage, conflicts)
  console.log(JSON.stringify(result))
  if (process.env.GITHUB_OUTPUT) for (const [k, v] of Object.entries(result)) appendFileSync(process.env.GITHUB_OUTPUT, `${k}=${v}\n`)
}
