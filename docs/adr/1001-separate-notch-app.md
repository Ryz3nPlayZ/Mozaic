# ADR-1001: Ship Mozaic Notch as a separate app

## Status

Accepted

## Context

Mozaic Notch (a fork of boring.notch) used to ship nested at
`Mozaic.app/Contents/Helpers/MozaicNotch.app`. macOS TCC attributes a nested
helper's privacy requests to the outer bundle, so camera, microphone, calendar,
Bluetooth, and Apple Events prompts were evaluated against Mozaic's sandboxed
identity. When Mozaic lacked a usage string, `tccd` terminated the notch during
onboarding. Every notch feature also widened the music player's entitlements.

Apps that ship a notch alongside other tools without conflicts, such as
Vorssaint, are one unsandboxed app with one Info.plist and one TCC identity.
Mozaic cannot do that without dropping its sandbox and diverging from Kaset.

## Decision

The notch is its own top-level app, `/Applications/Mozaic Notch.app`
(`com.zemuliu.MozaicNotch`). Its source is the boring.notch fork, vendored in
`Notch/` as a squashed git subtree so one checkout and one release workflow
build both apps. The fork's project sets the bundle ID, product name, and usage
strings, so no post-build plist rewriting is needed. Upstream changes come in
with:

```bash
git subtree pull --prefix=Notch https://github.com/TheBoredTeam/boring.notch main --squash
```

`Notch/` keeps its GPL-3.0 license. Mozaic does not link against it; the two
apps are shipped side by side.

`Scripts/build-notch.sh` builds and signs it (with the notch's own
entitlements) using Mozaic's `version.env`, so both apps carry the same version.
Each release ships:

- `mozaic-vX.dmg`: both apps and an Applications link, used by people and by
  the Homebrew cask, which installs both apps.
- `mozaic-vX.zip` and `mozaic-notch-vX.zip`: per-app Sparkle archives, listed
  in `appcast.xml` and `notch-appcast.xml`, signed with the same EdDSA key.

Mozaic does not embed the notch. When Mozaic Notch is installed and not
already running, Mozaic opens it at launch, as the embedded helper used to.

## Consequences

- Each app owns its TCC identity, so a permission prompt can no longer kill
  the other process, and the music player stays sandboxed.
- Each fork merges its own upstream (Kaset, boring.notch) independently.
- One download installs both apps; each app updates itself from its own feed.
- Updating from 1.0, where the notch was embedded, removes the notch until the
  user installs Mozaic Notch from the DMG or the cask.
