import { describe, expect, it } from 'vitest'
import { compareTags, parseTag, selectRelease, type UpstreamRelease } from '../../../scripts/linux-dist/check-upstream-release.mjs'

describe('Linux upstream release selection', () => {
  it('parses stable and release-candidate tags only', () => {
    expect(parseTag('dsh-v0.2.2-rc.4')).toEqual([0n, 2n, 2n, 4n])
    expect(parseTag('dsh-v0.2.2')).toEqual([0n, 2n, 2n, null])
    for (const tag of ['v0.2.2', 'dsh-v0.2', 'dsh-v0.2.2-beta.1', 'dsh-v0.2.2-rc.']) expect(parseTag(tag)).toBeNull()
  })

  it('orders stable releases after every release candidate', () => {
    expect(compareTags('dsh-v0.2.2', 'dsh-v0.2.2-rc.99')).toBe(1)
    expect(compareTags('dsh-v0.2.2-rc.4', 'dsh-v0.2.2-rc.5')).toBe(-1)
    expect(compareTags('dsh-v0.2.2-rc.5', 'dsh-v0.2.2-rc.5')).toBe(0)
    expect(compareTags('dsh-v0.2.3-rc.1', 'dsh-v0.2.2')).toBe(1)
    expect(() => compareTags('dsh-v0.2.2', 'latest')).toThrow(/stable or rc/u)
  })

  it('selects only the newest newer published release', () => {
    const releases: UpstreamRelease[] = [
      { tag_name: 'dsh-v0.2.0', draft: false },
      { tag_name: 'dsh-v0.2.2', draft: false },
      { tag_name: 'dsh-v0.2.1', draft: false },
      { tag_name: 'dsh-v0.3.0-rc.1', draft: true },
      { tag_name: 'dsh-v0.3.0-rc.2', draft: false },
      { tag_name: 'nightly', draft: false },
    ]
    expect(selectRelease(releases, 'dsh-v0.2.0')).toBe('dsh-v0.3.0-rc.2')
    expect(selectRelease(releases, 'dsh-v0.3.0-rc.2')).toBe('')
  })
})
