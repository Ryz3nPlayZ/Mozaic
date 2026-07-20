import Foundation
import Testing
@testable import Mozaic

@Suite("YouTubeWatchWebView scripts", .tags(.service))
@MainActor
struct YouTubeWatchScriptTests {
    @Test("Observer script posts to the youtubePlayer bridge with both message types")
    func observerScriptContract() {
        let script = YouTubeWatchWebView.observerScript
        #expect(script.contains("webkit.messageHandlers.youtubePlayer"))
        #expect(script.contains("STATE_UPDATE"))
        #expect(script.contains("VIDEO_ENDED"))
        #expect(script.contains("movie_player"))
        #expect(script.contains("__mozaicTargetVolume"))
    }

    @Test("Extraction script defines the callable hook and visibility chain")
    func extractionScriptContract() {
        let script = YouTubeWatchWebView.extractionScript
        #expect(script.contains("__mozaicExtractVideo"))
        #expect(script.contains("mozaic-yt-video-style"))
        #expect(script.contains("mozaic-visible"))
        #expect(script.contains("ytp-chrome-bottom"))
    }

    @Test("Bootstrap script clamps the volume target")
    func bootstrapClampsVolume() {
        #expect(YouTubeWatchWebView.pageBootstrapScript(targetVolume: 2.0)
            .contains("__mozaicTargetVolume = 1.0"))
        #expect(YouTubeWatchWebView.pageBootstrapScript(targetVolume: -1)
            .contains("__mozaicTargetVolume = 0.0"))
    }

    @Test("Bootstrap carries a pending resume-seek only when present and positive")
    func bootstrapCarriesPendingSeek() {
        #expect(YouTubeWatchWebView.pageBootstrapScript(targetVolume: 1, pendingSeek: 42.5)
            .contains("__mozaicPendingSeek = 42.5"))
        // No seek pending → no marker injected.
        #expect(!YouTubeWatchWebView.pageBootstrapScript(targetVolume: 1, pendingSeek: nil)
            .contains("__mozaicPendingSeek"))
        // Zero/negative is not a resume position.
        #expect(!YouTubeWatchWebView.pageBootstrapScript(targetVolume: 1, pendingSeek: 0)
            .contains("__mozaicPendingSeek"))
    }

    @Test("Observer applies the pending seek gated on a seekable element")
    func observerAppliesPendingSeekWhenReady() {
        let script = YouTubeWatchWebView.observerScript
        // The seek is applied by the observer (not a one-shot at didFinish),
        // gated on readyState so it survives YouTube creating <video> late.
        #expect(script.contains("__mozaicPendingSeek"))
        #expect(script.contains("applyPendingSeek"))
        #expect(script.contains("readyState"))
    }

    @Test("Observer skips the pending seek while an ad is showing")
    func observerSkipsPendingSeekDuringAd() {
        let script = YouTubeWatchWebView.observerScript
        // applyPendingSeek must bail on isAdShowing() so a preroll-ad element
        // doesn't consume the seek and leave content starting from 0.
        #expect(script.contains("isAdShowing()"))
    }

    @Test("A normal loadVideo clears a stale pending seek from an interrupted reload")
    func normalLoadClearsStalePendingSeek() {
        let webView = YouTubeWatchWebView.shared
        webView.pendingSeek = 99
        // loadVideo (the non-reload path) must drop the leftover seek so it can't
        // be injected into a different video. (No webView attached in tests, so
        // the load is a no-op beyond clearing the field.)
        webView.loadVideo(videoId: "different-video")
        #expect(webView.pendingSeek == nil)
    }
}
