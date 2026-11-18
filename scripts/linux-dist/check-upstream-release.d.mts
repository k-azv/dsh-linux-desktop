/** Minimal GitHub Release fields used to select the next upstream tag. */
export interface UpstreamRelease {
  readonly tag_name: string
  readonly draft: boolean
}

/**
 * Parse one stable or release-candidate downstream source tag.
 * @param tag GitHub Release tag.
 * @returns Version components in comparison order, or null when the tag is unsupported.
 */
export function parseTag(tag: string): readonly [bigint, bigint, bigint, bigint | null] | null

/**
 * Compare two source tags using release-candidate ordering.
 * @param a Left tag.
 * @param b Right tag.
 * @returns -1, 0, or 1 when the left tag is older, equal, or newer.
 */
export function compareTags(a: string, b: string): -1 | 0 | 1

/**
 * Select the newest published tag newer than the downstream state.
 * @param releases GitHub Releases from every page.
 * @param current Last synchronized source tag.
 * @returns Selected tag, or an empty string when no newer release exists.
 */
export function selectRelease(releases: readonly UpstreamRelease[], current: string): string
