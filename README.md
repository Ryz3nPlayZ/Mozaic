# Mozaic

Mozaic is a native macOS client for YouTube Music and YouTube, built using Swift and SwiftUI. It provides an integrated audio and video experience with a native interface, system media key controls, and a custom equalizer.

## Features

- Native macOS interface with sidebar navigation and a custom player.
- YouTube Music integration supporting full playback of YouTube Music content.
- YouTube integration for browsing recommendations, subscriptions, and video playback with native controls.
- Playback Arbiter for managing audio focus and media keys between music and video states.
- System-wide 6-band parametric equalizer applied directly to playback.
- System integration including the macOS Now Playing widget, Control Center, and media key support.
- Localized interface supporting English, French, Korean, Indonesian, Turkish, and Arabic.
- AppleScript support for remote automation and system integration.
- Extension support for loading WebKit Web Extensions (such as ad blockers).

## Requirements

- macOS 15.4 or later
- Google account for personalized content and subscriptions

## Installation

### Binary Download

Download the latest release DMG from the Releases page. Drag and drop the Mozaic application into your Applications folder.

Since the application is ad-hoc signed, you may need to remove the quarantine attribute after installation:

```bash
xattr -cr /Applications/Mozaic.app
```

### Homebrew

```bash
brew install Ryz3nPlayZ/repo/mozaic
```

## Contributing

See CONTRIBUTING.md for details regarding local development setup, codebase architecture, and contributing guidelines.
