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
(`com.zemuliu.MozaicNotch`). It has its own Info.plist usage strings,
entitlements, and Sparkle feed. It is built and released from the
boring.notch fork.

Mozaic does not embed or launch it. Mozaic only offers it: when the notch app
is installed, Mozaic can open it, and otherwise it links to the download. The
Homebrew tap ships it as a separate cask (`mozaic-notch`).

## Consequences

- Each app owns its TCC identity, so a permission prompt can no longer kill
  the other process, and the music player stays sandboxed.
- Each fork merges its own upstream (Kaset, boring.notch) independently.
- Two downloads and two update feeds, which the cask and the in-app link
  keep simple.
