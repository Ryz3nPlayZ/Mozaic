import Testing
@testable import Mozaic

@Suite("YouTube interstitial script contracts", .tags(.service))
@MainActor
struct YouTubeInterstitialScriptContractTests {
    @Test("Reveal matches the blackout and extraction contracts")
    func interstitialRevealContract() {
        let reveal = YouTubeWatchWebView.revealInterstitialScript
        let blackout = YouTubeWatchWebView.blackoutScript
        let extraction = YouTubeWatchWebView.extractionScript

        #expect(blackout.contains("style.id = 'mozaic-yt-blackout'"))
        #expect(extraction.contains("const styleId = 'mozaic-yt-video-style'"))
        #expect(extraction.contains("window.__mozaicStopYTExtraction = stopExtraction"))
        #expect(reveal.contains("typeof window.__mozaicStopYTExtraction === 'function'"))
        #expect(reveal.contains("'mozaic-yt-blackout', 'mozaic-yt-video-style'"))
    }
}
