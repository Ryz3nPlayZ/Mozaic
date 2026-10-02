import Foundation
import JavaScriptCore
import Testing
@testable import Mozaic

@Suite("PlaybackAdBlocker")
@MainActor
struct PlaybackAdBlockerTests {
    private func makeContext() throws -> JSContext {
        let context = try #require(JSContext())
        context.evaluateScript(PlaybackAdBlocker.userScriptSource)
        #expect(context.exception == nil)
        return context
    }

    @Test("JSON.parse strips ad payloads from player responses")
    func stripsAdsFromPlayerResponse() throws {
        let context = try self.makeContext()
        let result = context.evaluateScript("""
        (function() {
            const r = JSON.parse('{"videoDetails":{"videoId":"abc"},"streamingData":{},"adPlacements":[1],"adSlots":[2],"playerAds":[3]}');
            return [('adPlacements' in r), ('adSlots' in r), ('playerAds' in r), r.videoDetails.videoId].join(',');
        })()
        """)
        #expect(result?.toString() == "false,false,false,abc")
    }

    @Test("Nested next-endpoint player responses are pruned")
    func stripsNestedPlayerResponse() throws {
        let context = try self.makeContext()
        let result = context.evaluateScript("""
        (function() {
            const r = JSON.parse('[{"playerResponse":{"playabilityStatus":{},"adPlacements":[1]}},{"response":{}}]');
            return String('adPlacements' in r[0].playerResponse);
        })()
        """)
        #expect(result?.toString() == "false")
    }

    @Test("Non-player JSON is left untouched")
    func leavesOtherJSONAlone() throws {
        let context = try self.makeContext()
        let result = context.evaluateScript("""
        (function() {
            const r = JSON.parse('{"contents":{},"adSlots":[1]}');
            return String('adSlots' in r);
        })()
        """)
        #expect(result?.toString() == "true")
    }

    @Test("Script installs only once per page")
    func installsOnce() throws {
        let context = try self.makeContext()
        context.evaluateScript("const firstParse = JSON.parse;")
        context.evaluateScript(PlaybackAdBlocker.userScriptSource)
        #expect(context.evaluateScript("JSON.parse === firstParse")?.toBool() == true)
    }

    @Test("Content rules are valid block rules for ad hosts only")
    func contentRulesAreWellFormed() throws {
        let data = try #require(PlaybackAdBlocker.encodedContentRules.data(using: .utf8))
        let rules = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: [String: String]]])

        #expect(rules.count == PlaybackAdBlocker.blockedURLFilters.count)
        for rule in rules {
            #expect(rule["action"]?["type"] == "block")
            let filter = try #require(rule["trigger"]?["url-filter"])
            let regex = try NSRegularExpression(pattern: filter)
            for playbackURL in [
                "https://music.youtube.com/youtubei/v1/player",
                "https://rr1---sn-abc.googlevideo.com/videoplayback?id=1",
                "https://www.youtube.com/api/stats/watchtime",
            ] {
                let range = NSRange(playbackURL.startIndex..., in: playbackURL)
                #expect(regex.firstMatch(in: playbackURL, range: range) == nil, "\(filter) blocks \(playbackURL)")
            }
        }
    }

    @Test("Ad hosts match a blocking rule")
    func adHostsAreBlocked() throws {
        let regexes = try PlaybackAdBlocker.blockedURLFilters.map { try NSRegularExpression(pattern: $0) }
        for adURL in [
            "https://googleads.g.doubleclick.net/pagead/id",
            "https://www.youtube.com/pagead/adview?ai=1",
            "https://music.youtube.com/api/stats/ads?ver=2",
            "https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js",
        ] {
            let range = NSRange(adURL.startIndex..., in: adURL)
            #expect(regexes.contains { $0.firstMatch(in: adURL, range: range) != nil }, "\(adURL) not blocked")
        }
    }

    @Test("Missing blockAds value loads as true")
    func missingBlockAdsLoadsAsTrue() throws {
        let suiteName = "PlaybackAdBlockerTests.blockAds.missing.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(SettingsManager.loadBlockAds(from: defaults) == true)
    }

    @Test("Stored false blockAds value loads as false")
    func storedFalseBlockAdsLoadsAsFalse() throws {
        let suiteName = "PlaybackAdBlockerTests.blockAds.false.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(false, forKey: SettingsManager.Keys.blockAds)

        #expect(SettingsManager.loadBlockAds(from: defaults) == false)
    }
}
