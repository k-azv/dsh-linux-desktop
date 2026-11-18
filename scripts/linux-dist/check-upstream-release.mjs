#!/usr/bin/env node
import { execFileSync } from 'node:child_process'
import { readFileSync, appendFileSync } from 'node:fs'

// Deliberately support only the upstream stable/rc release contract.
export function parseTag(tag) {
  const m = /^dsh-v(\d+)\.(\d+)\.(\d+)(?:-rc\.(\d+))?$/.exec(tag)
  return m && [BigInt(m[1]), BigInt(m[2]), BigInt(m[3]), m[4] === undefined ? null : BigInt(m[4])]
}
export function compareTags(a, b) {
  const x = parseTag(a), y = parseTag(b)
  if (!x || !y) throw new Error('Expected stable or rc dsh-v tags')
  for (let i = 0; i < 3; i++) if (x[i] !== y[i]) return x[i] > y[i] ? 1 : -1
  const xrc = x[3], yrc = y[3]
  if (xrc === yrc) return 0
  if (xrc === null) return 1
  if (yrc === null) return -1
  return xrc > yrc ? 1 : -1
}
export function selectRelease(releases, current) {
  return releases.filter(r => !r.draft && parseTag(r.tag_name) && compareTags(r.tag_name, current) > 0)
    .sort((a, b) => compareTags(b.tag_name, a.tag_name))[0]?.tag_name ?? ''
}
if (process.argv[1] && import.meta.url === new URL(process.argv[1], 'file:').href) {
  const current = readFileSync(new URL('./state/last-synced-tag.txt', import.meta.url), 'utf8').trim()
  if (!parseTag(current)) throw new Error(`Invalid sync state: ${current}`)
  // --slurp keeps pagination as JSON, including rc releases with prerelease=true.
  const pages = JSON.parse(execFileSync('gh', ['api', '--paginate', '--slurp',
    'repos/deepseek-ai/deepseek-harness/releases?per_page=100'], { encoding: 'utf8' }))
  const tag = selectRelease(pages.flat(), current)
  console.log(tag || `Already synced through ${current}`)
  if (process.env.GITHUB_OUTPUT) appendFileSync(process.env.GITHUB_OUTPUT, `target_tag=${tag}\n`)
}
