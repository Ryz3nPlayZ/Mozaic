import Foundation
import os

/// Centralized logging for the Mozaic app.
enum DiagnosticsLogger {
    /// Logger for authentication-related events.
    static let auth = Logger(subsystem: "com.zemuliu.Mozaic", category: "Auth")

    /// Logger for API-related events.
    static let api = Logger(subsystem: "com.zemuliu.Mozaic", category: "API")

    /// Logger for WebKit-related events.
    static let webKit = Logger(subsystem: "com.zemuliu.Mozaic", category: "WebKit")

    /// Logger for player-related events.
    static let player = Logger(subsystem: "com.zemuliu.Mozaic", category: "Player")

    /// Logger for UI-related events.
    static let ui = Logger(subsystem: "com.zemuliu.Mozaic", category: "UI")

    /// Logger for notification-related events.
    static let notification = Logger(subsystem: "com.zemuliu.Mozaic", category: "Notification")

    /// Logger for AI/Foundation Models-related events.
    static let ai = Logger(subsystem: "com.zemuliu.Mozaic", category: "AI")

    /// Logger for haptic feedback-related events.
    static let haptic = Logger(subsystem: "com.zemuliu.Mozaic", category: "Haptic")

    /// Logger for network connectivity-related events.
    static let network = Logger(subsystem: "com.zemuliu.Mozaic", category: "Network")

    /// Logger for updater/general app events.
    static let updater = Logger(subsystem: "com.zemuliu.Mozaic", category: "Updater")

    /// Logger for app lifecycle and URL handling events.
    static let app = Logger(subsystem: "com.zemuliu.Mozaic", category: "App")

    /// Logger for AppleScript scripting events.
    static let scripting = Logger(subsystem: "com.zemuliu.Mozaic", category: "Scripting")

    /// Logger for AirPlay-related events.
    static let airplay = Logger(subsystem: "com.zemuliu.Mozaic", category: "AirPlay")

    /// Logger for scrobbling-related events (Last.fm, etc.).
    static let scrobbling = Logger(subsystem: "com.zemuliu.Mozaic", category: "Scrobbling")

    /// Logger for web extension management events.
    static let extensions = Logger(subsystem: "com.zemuliu.Mozaic", category: "Extensions")

    /// Logger for listening history-related events.
    static let history = Logger(subsystem: "com.zemuliu.Mozaic", category: "History")

    /// Logger for the equalizer subsystem (process tap, HAL I/O, DSP).
    static let equalizer = Logger(subsystem: "com.zemuliu.Mozaic", category: "Equalizer")
}
