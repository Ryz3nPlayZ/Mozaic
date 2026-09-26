import WebKit

// MARK: - SingletonPlayerWebView Playback Controls Extension

extension SingletonPlayerWebView {
    /// Enables/disables startup autoplay blocking inside the observer script.
    func setAutoplayBlocked(_ blocked: Bool) {
        guard let webView else { return }
        let script = """
            (function() {
                window.__mozaicBlockAutoplay = \(blocked ? "true" : "false");
                if (window.__mozaicAutoplayBlockTimer) {
                    clearInterval(window.__mozaicAutoplayBlockTimer);
                    window.__mozaicAutoplayBlockTimer = null;
                }
                if (!window.__mozaicBlockAutoplay) return 'autoplay-allowed';
                window.__mozaicAutoplayPending = false;
                \(WebPlaybackAudioOutput.stopScript)
                var ticks = 0;
                const timer = setInterval(function() {
                    if (!window.__mozaicBlockAutoplay) {
                        clearInterval(timer);
                        if (window.__mozaicAutoplayBlockTimer === timer) window.__mozaicAutoplayBlockTimer = null;
                        return;
                    }
                    const video = document.querySelector('video');
                    if (video && !video.paused) {
                        try { video.pause(); } catch (_) {}
                    }
                    ticks += 1;
                    if (ticks >= 20) {
                        clearInterval(timer);
                        if (window.__mozaicAutoplayBlockTimer === timer) window.__mozaicAutoplayBlockTimer = null;
                    }
                }, 150);
                window.__mozaicAutoplayBlockTimer = timer;
                return 'autoplay-blocked';
            })();
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    struct PlaybackSnapshot {
        let progress: TimeInterval
        let duration: TimeInterval
        let videoId: String?
    }

    nonisolated static let playbackSnapshotScript = """
        (function() {
            const video = document.querySelector('video');
            if (!video || video.readyState < 1 || !video.__mozaicBoundVideoId
                || !(video.__mozaicMediaGeneration > 0)) return null;
            const source = video.currentSrc || video.src || '';
            if (!source || source !== video.__mozaicBoundMediaSource) return null;
            return {
                progress: Number.isFinite(video.currentTime) ? video.currentTime : 0,
                duration: Number.isFinite(video.duration) ? video.duration : 0,
                videoId: video.__mozaicBoundVideoId
            };
        })();
    """

    /// Reads playback time from the live WebView video element.
    func currentPlaybackSnapshot() async -> PlaybackSnapshot? {
        guard let webView else { return nil }

        return await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(Self.playbackSnapshotScript) { result, error in
                if let error {
                    self.logger.error("currentPlaybackSnapshot error: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }

                guard let dictionary = result as? [String: Any] else {
                    continuation.resume(returning: nil)
                    return
                }

                let progress = Self.timeInterval(from: dictionary["progress"])
                let duration = Self.timeInterval(from: dictionary["duration"])
                let videoId = (dictionary["videoId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                continuation.resume(returning: PlaybackSnapshot(
                    progress: progress,
                    duration: duration,
                    videoId: videoId
                ))
            }
        }
    }

    private static func timeInterval(from value: Any?) -> TimeInterval {
        switch value {
        case let number as NSNumber:
            number.doubleValue
        case let double as Double:
            double
        case let string as String:
            Double(string) ?? 0
        default:
            0
        }
    }

    nonisolated static var playPauseCommandScript: String {
        """
        (function() {
            const playBtn = document.querySelector('.play-pause-button.ytmusic-player-bar');
            if (playBtn) {
                const video = document.querySelector('video');
                const wantsPlay = !video || video.paused;
                window.__mozaicAutoplayPending = wantsPlay;
                window.__mozaicPlaybackSuppressed = !wantsPlay;
                if (wantsPlay) {
                    window.__mozaicBlockAutoplay = false;
                    \(WebPlaybackAudioOutput.prepareScript)
                    window.__mozaicAutoplayAttempts = 0;
                    window.__mozaicAutoplayRetryScheduled = false;
                    if (video && typeof window.__mozaicAttemptAutoplayRecovery === 'function') {
                        return window.__mozaicAttemptAutoplayRecovery(video, playBtn);
                    }
                } else {
                    \(WebPlaybackAudioOutput.stopScript)
                }
                playBtn.click();
                return 'clicked';
            }
            const video = document.querySelector('video');
            if (video) {
                if (video.paused) {
                    window.__mozaicAutoplayPending = true;
                    window.__mozaicPlaybackSuppressed = false;
                    window.__mozaicBlockAutoplay = false;
                    \(WebPlaybackAudioOutput.prepareScript)
                    window.__mozaicAutoplayAttempts = 0;
                    window.__mozaicAutoplayRetryScheduled = false;
                    if (typeof window.__mozaicAttemptAutoplayRecovery === 'function') {
                        return window.__mozaicAttemptAutoplayRecovery(video, null);
                    }
                    video.play();
                    return 'played';
                } else {
                    window.__mozaicAutoplayPending = false;
                    window.__mozaicPlaybackSuppressed = true;
                    \(WebPlaybackAudioOutput.stopScript)
                    video.pause();
                    return 'paused';
                }
            }
            return 'no-element';
        })();
        """
    }

    /// Toggle play/pause.
    func playPause() {
        guard let webView else { return }
        let generation = self.documentGeneration.currentGeneration
        guard self.documentGeneration.accepts(generation: generation) else { return }

        let script = """
            if (window.__mozaicDocumentGeneration === \(generation)) {
                \(Self.playPauseCommandScript)
            }
        """
        webView.evaluateJavaScript(script) { [weak self] _, error in
            if let error {
                self?.logger.error("playPause error: \(error.localizedDescription)")
            }
        }
    }

    nonisolated static var playCommandScript: String {
        """
        (function() {
            window.__mozaicAutoplayPending = true;
            window.__mozaicPlaybackSuppressed = false;
            window.__mozaicBlockAutoplay = false;
            window.__mozaicResumeAdOnly = false;
            window.__mozaicAutoplayAttempts = 0;
            window.__mozaicAutoplayRetryScheduled = false;
            const video = document.querySelector('video');
            if (video && video.paused) {
                \(WebPlaybackAudioOutput.prepareScript)
                if (typeof window.__mozaicAttemptAutoplayRecovery === 'function') {
                    return window.__mozaicAttemptAutoplayRecovery(video, null);
                }
                video.play();
                return 'played';
            }
            return video ? 'already-playing' : 'pending-media';
        })();
        """
    }

    /// Play (resume).
    func play() {
        guard let webView else { return }
        let generation = self.documentGeneration.currentGeneration
        guard self.documentGeneration.accepts(generation: generation) else { return }
        webView.evaluateJavaScript("""
            if (window.__mozaicDocumentGeneration === \(generation)) {
                \(Self.playCommandScript)
            }
        """, completionHandler: nil)
    }

    /// During restored playback, a paused preroll ad must advance before the
    /// content seek can be reconciled. Never unsuppress ordinary content here.
    func resumeReadyAdvertisementIfPresent() {
        guard let webView else { return }
        let generation = self.documentGeneration.currentGeneration
        guard self.documentGeneration.accepts(generation: generation) else { return }
        webView.evaluateJavaScript("""
            (function() {
                if (window.__mozaicDocumentGeneration !== \(generation)) return 'stale';
                window.__mozaicBlockAutoplay = false;
                if (window.__mozaicAutoplayBlockTimer) {
                    clearInterval(window.__mozaicAutoplayBlockTimer);
                    window.__mozaicAutoplayBlockTimer = null;
                }
                \(PlaybackAdDetectionScript.detection)
                const isAd = isAdShowing();
                const video = document.querySelector('video');
                if (!isAd || !video || !video.currentSrc || video.readyState < 1) return 'not-ready-ad';
                window.__mozaicPlaybackSuppressed = false;
                window.__mozaicAutoplayPending = true;
                window.__mozaicResumeAdOnly = true;
                if (video.paused) {
                    if (typeof window.__mozaicAttemptAutoplayRecovery === 'function') {
                        window.__mozaicAttemptAutoplayRecovery(video, null);
                    } else {
                        video.play();
                    }
                }
                return 'playing-ad';
            })();
        """, completionHandler: nil)
    }

    /// Pause.
    func pause() {
        guard let webView else { return }

        let script = """
            (function() {
            window.__mozaicAutoplayPending = false;
            window.__mozaicPlaybackSuppressed = true;
            \(WebPlaybackAudioOutput.stopScript)
                const video = document.querySelector('video');
                if (video && !video.paused) { video.pause(); return 'paused'; }
                return 'already-paused';
            })();
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    /// Skip to next track.
    func next() {
        guard let webView else { return }

        let script = """
            (function() {
                const nextBtn = document.querySelector('.next-button.ytmusic-player-bar');
                if (nextBtn) { nextBtn.click(); return 'clicked'; }
                return 'no-button';
            })();
        """
        webView.evaluateJavaScript(script) { [weak self] _, error in
            if let error {
                self?.logger.error("next error: \(error.localizedDescription)")
            }
        }
    }

    /// Go to previous track.
    func previous() {
        guard let webView else { return }

        let script = """
            (function() {
                const prevBtn = document.querySelector('.previous-button.ytmusic-player-bar');
                if (prevBtn) { prevBtn.click(); return 'clicked'; }
                return 'no-button';
            })();
        """
        webView.evaluateJavaScript(script) { [weak self] _, error in
            if let error {
                self?.logger.error("previous error: \(error.localizedDescription)")
            }
        }
    }

    /// Seek to a specific time in seconds.
    func seek(to time: Double) {
        guard let webView else { return }

        let script = """
            (function() {
                const video = document.querySelector('video');
                if (video) { video.currentTime = \(time); return 'seeked'; }
                return 'no-video';
            })();
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    /// Pure script for atomically pausing and seeking the underlying video.
    nonisolated static func seekAndPauseScript(to time: Double) -> String {
        let safeTime = time.isFinite ? max(time, 0) : 0
        return """
            (function() {
                \(WebPlaybackAudioOutput.stopScript)
                const video = document.querySelector('video');
                if (!video) { return 'no-video'; }
                video.pause();
                video.currentTime = \(safeTime);
                video.pause();
                return 'seeked-paused';
            })();
        """
    }

    /// Atomically pause and seek the underlying video.
    func seekAndPause(to time: Double) {
        guard let webView else { return }
        webView.evaluateJavaScript(Self.seekAndPauseScript(to: time), completionHandler: nil)
    }

    /// Seeks to the start and resumes playback without a full page load (repeat-one, same-URL recovery).
    func restartInPlaceFromBeginning() {
        guard let webView else { return }
        if let nativeGeneration = self.coordinator?.playerService.currentMusicPlaybackOccurrence?.nativeGeneration {
            self.setNativePlaybackGeneration(nativeGeneration)
        }
        let documentGeneration = self.documentGeneration.currentGeneration
        guard self.documentGeneration.accepts(generation: documentGeneration) else { return }
        let script = """
            (function() {
                if (window.__mozaicDocumentGeneration !== \(documentGeneration)) return 'stale';
                window.__mozaicBlockAutoplay = false;
                if (window.__mozaicAutoplayBlockTimer) {
                    clearInterval(window.__mozaicAutoplayBlockTimer);
                    window.__mozaicAutoplayBlockTimer = null;
                }
                window.__mozaicAutoplayPending = true;
                window.__mozaicPlaybackSuppressed = false;
                window.__mozaicResumeAdOnly = false;
                window.__mozaicAutoplayAttempts = 0;
                window.__mozaicAutoplayRetryScheduled = false;
                const video = document.querySelector('video');
                if (!video) return 'no-video';
                video.currentTime = 0;
                if (typeof window.__mozaicAdvanceMediaGeneration === 'function') {
                    window.__mozaicAdvanceMediaGeneration();
                }
                if (typeof window.__mozaicAttemptAutoplayRecovery === 'function') {
                    window.__mozaicAttemptAutoplayRecovery(video, null);
                } else {
                    video.play();
                }
                return 'restarted';
            })();
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    /// Set volume (0.0 - 1.0).
    func setVolume(_ volume: Double) {
        guard let webView else { return }
        let clampedVolume = max(0, min(1, volume))

        // Update target volume and set video volume directly
        // Also try to set YouTube's internal player volume via their API
        let script = """
            (function() {
                window.__mozaicTargetVolume = \(clampedVolume);
                const video = document.querySelector('video');
                let result = [];

                if (video) {
                    // Set flag to prevent volumechange listener from reverting
                    window.__mozaicIsSettingVolume = true;
                    video.volume = \(clampedVolume);
                    result.push('video.volume=' + video.volume);
                    setTimeout(() => { window.__mozaicIsSettingVolume = false; }, 50);
                } else {
                    result.push('no-video');
                }

                // Also try YouTube Music's internal player API
                const player = document.querySelector('ytmusic-player');
                if (player && player.playerApi) {
                    const ytVolume = Math.round(\(clampedVolume) * 100);
                    player.playerApi.setVolume(ytVolume);
                    result.push('ytapi.setVolume=' + ytVolume);
                }

                // Try movie_player API as fallback
                const moviePlayer = document.getElementById('movie_player');
                if (moviePlayer && moviePlayer.setVolume) {
                    const ytVolume = Math.round(\(clampedVolume) * 100);
                    moviePlayer.setVolume(ytVolume);
                    result.push('movie_player.setVolume=' + ytVolume);
                }

                return result.join(', ');
            })();
        """
        webView.evaluateJavaScript(script) { _, error in
            if let error {
                self.logger.error("setVolume error: \(error.localizedDescription)")
            }
        }
    }

    /// Show the native AirPlay picker for the WebView's video element.
    func showAirPlayPicker(at screenPoint: CGPoint? = nil) {
        guard let webView else {
            DiagnosticsLogger.airplay.warning("showAirPlayPicker called but webView is nil")
            return
        }

        AirPlayPickerAnchor.preparePicker(in: webView, at: screenPoint)

        let script = """
            (function() {
                const video = document.querySelector('video');
                if (!video) return 'no-video';
                if (typeof video.webkitShowPlaybackTargetPicker !== 'function') return 'unsupported';

                video.webkitShowPlaybackTargetPicker();
                return 'picker-shown';
            })();
        """
        webView.evaluateJavaScript(script) { result, error in
            if let error {
                DiagnosticsLogger.airplay.error("showAirPlayPicker error: \(error.localizedDescription)")
            } else if let status = result as? String {
                switch status {
                case "no-video":
                    DiagnosticsLogger.airplay.warning("showAirPlayPicker: no video element available")
                case "unsupported":
                    DiagnosticsLogger.airplay.warning("showAirPlayPicker: webkitShowPlaybackTargetPicker not supported")
                default:
                    DiagnosticsLogger.airplay.debug("showAirPlayPicker: \(status)")
                }
            }
        }
    }
}
