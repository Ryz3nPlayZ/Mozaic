# ADR-1000: Built-in playback ad blocker

## Status

Accepted

Mozaic-specific ADRs are numbered from 1000 so they never collide with
upstream Kaset ADRs when the vendor branch is merged.

## Context

YouTube and YouTube Music play pre-roll and mid-roll ads inside the playback
WebViews. Mozaic must not add third-party dependencies, and playback,
watch-history stats, and the native ad-detection bridges
(`PlaybackAdDetectionScript`) must keep working.

## Decision

`PlaybackAdBlocker` installs on every playback WebView alongside the existing
user scripts, controlled by `SettingsManager.blockAds` (default on, shown under
General → Ad Blocking). It has three layers:

1. A document-start, main-frame script wraps `JSON.parse`,
   `Response.prototype.json`, and the `ytInitialPlayerResponse` global. It deletes
   `adPlacements`, `adSlots`, `playerAds`, and `adBreakHeartbeatParams` from
   objects that look like player responses. Other JSON is untouched.
2. A `WKContentRuleList` blocks hosts and paths that only serve or measure ads
   (`doubleclick.net`, `googlesyndication.com`, `googleadservices.com`,
   `/pagead/`, `/api/stats/ads`, `/get_midroll_info`). `videoplayback`,
   `/youtubei/v1/player`, and watch-time stats stay allowed.
3. If an ad still starts (e.g. server-stitched), the script clicks Skip, or
   seeks to the end of the ad.

Toggling applies from the next playback document load.

## Consequences

- No network proxy, no dependencies, and no change to the API clients.
- YouTube can rename response keys or player classes. The tests cover the
  pruning and rule shapes, and layer 3 limits the damage when layer 1 misses.
- Ad-state signals may still fire briefly for ads that reach the player, so the
  existing ad-detection bridges keep their behavior.
