import Foundation
import os
import WebKit

/// Built-in ad blocking for the YouTube and YouTube Music playback WebViews.
///
/// Three layers, cheapest first:
/// 1. A document-start script prunes ad payloads (`adPlacements`, `adSlots`, `playerAds`)
///    from player responses before YouTube's player reads them, so most ads are never scheduled.
/// 2. A WebKit content rule list blocks ad-serving and ad-measurement hosts.
/// 3. If an ad still starts (e.g. server-stitched), the script clicks Skip or jumps to the
///    ad's end so content resumes. The existing `PlaybackAdDetectionScript` signals still
///    report the brief ad state to the native bridges.
@MainActor
enum PlaybackAdBlocker {
    static let ruleListIdentifier = "com.zemuliu.Mozaic.playback-ad-blocker.v1"

    private static let logger = DiagnosticsLogger.webKit
    private static var ruleListTask: Task<WKContentRuleList?, Never>?

    /// Installs (or removes) ad blocking on a playback WebView's content controller.
    /// Call from the same place that (re)installs the playback user scripts.
    static func install(on contentController: WKUserContentController, enabled: Bool) {
        guard enabled else {
            contentController.removeAllContentRuleLists()
            return
        }

        contentController.addUserScript(WKUserScript(
            source: self.userScriptSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))

        Task { @MainActor in
            guard let ruleList = await self.compiledRuleList() else { return }
            contentController.add(ruleList)
        }
    }

    /// Compiles the rule list once per launch and caches it in WebKit's store.
    static func compiledRuleList() async -> WKContentRuleList? {
        if let ruleListTask = self.ruleListTask {
            return await ruleListTask.value
        }

        let task = Task<WKContentRuleList?, Never> { @MainActor in
            guard let store = WKContentRuleListStore.default() else { return nil }
            do {
                return try await store.compileContentRuleList(
                    forIdentifier: self.ruleListIdentifier,
                    encodedContentRuleList: self.encodedContentRules
                )
            } catch {
                self.logger.error("Failed to compile ad-blocking rules: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
        self.ruleListTask = task
        return await task.value
    }

    /// Hosts and paths that only serve or measure ads. Playback, stats needed for
    /// watch history, and `ptracking` are intentionally left alone.
    nonisolated static let blockedURLFilters: [String] = [
        #"^[^:]+://+([^:/]+\.)?doubleclick\.net[:/]"#,
        #"^[^:]+://+([^:/]+\.)?googlesyndication\.com[:/]"#,
        #"^[^:]+://+([^:/]+\.)?googleadservices\.com[:/]"#,
        #"^[^:]+://+([^:/]+\.)?youtube\.com/pagead/"#,
        #"^[^:]+://+([^:/]+\.)?youtube\.com/api/stats/ads"#,
        #"^[^:]+://+([^:/]+\.)?youtube\.com/get_midroll_info"#,
    ]

    nonisolated static var encodedContentRules: String {
        let rules: [[String: [String: String]]] = self.blockedURLFilters.map { filter in
            ["trigger": ["url-filter": filter], "action": ["type": "block"]]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: rules),
              let json = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return json
    }

    nonisolated static var userScriptSource: String {
        """
        (function() {
            'use strict';
            const root = typeof globalThis !== 'undefined' ? globalThis : window;
            if (root.__mozaicAdBlocker) return;

            const AD_KEYS = ['adPlacements', 'adSlots', 'playerAds', 'adBreakHeartbeatParams'];

            function isPlayerResponse(value) {
                return !!value && typeof value === 'object'
                    && ('streamingData' in value || 'videoDetails' in value || 'playabilityStatus' in value);
            }

            function prune(value) {
                if (!value || typeof value !== 'object') return value;
                try {
                    const targets = [value, value.playerResponse];
                    if (Array.isArray(value)) {
                        for (const entry of value) {
                            if (entry && typeof entry === 'object') targets.push(entry.playerResponse);
                        }
                    }
                    for (const target of targets) {
                        if (!isPlayerResponse(target)) continue;
                        for (const key of AD_KEYS) {
                            if (key in target) delete target[key];
                        }
                    }
                } catch (e) {}
                return value;
            }

            root.__mozaicAdBlocker = { prune: prune };

            const nativeParse = JSON.parse;
            JSON.parse = function() {
                return prune(nativeParse.apply(this, arguments));
            };

            if (typeof Response !== 'undefined' && Response.prototype && Response.prototype.json) {
                const nativeJSON = Response.prototype.json;
                Response.prototype.json = function() {
                    return nativeJSON.apply(this, arguments).then(prune);
                };
            }

            // The first watch page embeds its player response as a global.
            try {
                let initialPlayerResponse = root.ytInitialPlayerResponse;
                Object.defineProperty(root, 'ytInitialPlayerResponse', {
                    configurable: true,
                    get: function() { return initialPlayerResponse; },
                    set: function(value) { initialPlayerResponse = prune(value); }
                });
            } catch (e) {}

            if (typeof document === 'undefined') return;

            // Fallback for ads that still reach the player (e.g. server-stitched).
            function skipActiveAd() {
                const player = document.getElementById('movie_player');
                if (!player || !player.classList) return;
                if (!player.classList.contains('ad-showing') && !player.classList.contains('ad-interrupting')) return;

                const skipButton = player.querySelector(
                    '.ytp-skip-ad-button, .ytp-ad-skip-button, .ytp-ad-skip-button-modern'
                );
                if (skipButton) {
                    skipButton.click();
                    return;
                }

                const video = player.querySelector('video');
                if (video && isFinite(video.duration) && video.duration > 0
                    && video.currentTime < video.duration - 0.25) {
                    video.currentTime = video.duration - 0.1;
                }
            }

            let observedPlayer = null;
            let classObserver = null;
            function attach() {
                const player = document.getElementById('movie_player');
                if (player && player !== observedPlayer && typeof MutationObserver === 'function') {
                    if (classObserver) classObserver.disconnect();
                    observedPlayer = player;
                    classObserver = new MutationObserver(skipActiveAd);
                    classObserver.observe(player, { attributes: true, attributeFilter: ['class'] });
                }
                skipActiveAd();
            }

            // Cheap poll: re-attaches when YouTube recreates the player and
            // catches ad states that change without a class mutation.
            setInterval(attach, 500);
        })();
        """
    }
}
