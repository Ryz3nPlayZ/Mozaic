import Foundation
import Observation

// MARK: - PlaylistImportMatch

/// An imported track and the YouTube Music song chosen for it, if any.
struct PlaylistImportMatch: Identifiable, Sendable {
    let id: Int
    let track: ImportedTrack
    var song: Song?
}

// MARK: - PlaylistImportViewModel

/// Drives importing a Spotify (or other) playlist export into a new YouTube
/// Music playlist: read the file, match each track with song search, then
/// create a private playlist from the matches (ADR-1002).
@MainActor
@Observable
final class PlaylistImportViewModel {
    enum Phase: Equatable {
        case choosingFile
        case ready
        case matching(completed: Int, total: Int)
        case reviewing
        case creating
        case finished(Playlist)
        case failed(String)
    }

    /// Searches run with this many requests in flight.
    static let maxConcurrentSearches = 4

    private(set) var phase: Phase = .choosingFile
    private(set) var playlists: [ImportedPlaylist] = []
    var selectedPlaylistID: ImportedPlaylist.ID?
    var title = ""
    private(set) var matches: [PlaylistImportMatch] = []

    var selectedPlaylist: ImportedPlaylist? {
        self.playlists.first { $0.id == self.selectedPlaylistID }
    }

    var matchedSongs: [Song] {
        self.matches.compactMap(\.song)
    }

    var unmatchedTracks: [ImportedTrack] {
        self.matches.filter { $0.song == nil }.map(\.track)
    }

    private let client: any YTMusicClientProtocol
    private let logger = DiagnosticsLogger.api

    init(client: any YTMusicClientProtocol) {
        self.client = client
    }

    // MARK: Loading

    /// Reads a user-selected export file.
    func load(fileURL: URL) {
        let didAccess = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let data = try Data(contentsOf: fileURL)
            self.load(data: data, fileName: fileURL.lastPathComponent)
        } catch {
            self.phase = .failed(PlaylistImportError.unreadable.localizedDescription)
        }
    }

    /// Parses export data and selects its first playlist.
    func load(data: Data, fileName: String) {
        do {
            self.playlists = try PlaylistImportParser.parse(data: data, fileName: fileName)
            self.selectPlaylist(self.playlists.first?.id)
            self.phase = .ready
        } catch {
            self.phase = .failed(error.localizedDescription)
        }
    }

    func selectPlaylist(_ id: ImportedPlaylist.ID?) {
        self.selectedPlaylistID = id
        self.title = self.selectedPlaylist?.name ?? ""
    }

    // MARK: Matching

    /// Searches YouTube Music for every track in the selected playlist.
    func matchTracks() async {
        guard self.phase == .ready, let playlist = self.selectedPlaylist else { return }
        let tracks = playlist.tracks
        let client = self.client
        var results = tracks.enumerated().map { PlaylistImportMatch(id: $0.offset, track: $0.element) }
        self.phase = .matching(completed: 0, total: tracks.count)

        var failedSearches = 0
        await withTaskGroup(of: (index: Int, song: Song?, failed: Bool).self) { group in
            var nextIndex = 0
            func enqueueNext() {
                guard nextIndex < tracks.count else { return }
                let index = nextIndex
                let track = tracks[index]
                nextIndex += 1
                group.addTask {
                    do {
                        let candidates = try await client.searchSongs(query: PlaylistTrackMatcher.searchQuery(for: track))
                        return (index, PlaylistTrackMatcher.bestMatch(for: track, in: candidates), false)
                    } catch {
                        return (index, nil, true)
                    }
                }
            }

            for _ in 0 ..< Self.maxConcurrentSearches {
                enqueueNext()
            }
            var completed = 0
            for await result in group {
                results[result.index].song = result.song
                if result.failed {
                    failedSearches += 1
                }
                completed += 1
                self.phase = .matching(completed: completed, total: tracks.count)
                enqueueNext()
            }
        }

        guard !Task.isCancelled else { return }
        if failedSearches == tracks.count {
            self.phase = .failed(String(localized: "Couldn't search YouTube Music. Check your connection and sign-in, then try again."))
            return
        }
        self.matches = results
        self.phase = .reviewing
        self.logger.info("Playlist import matched \(self.matchedSongs.count)/\(tracks.count) tracks")
    }

    // MARK: Creating

    /// Creates a private YouTube Music playlist from the matched songs.
    func createPlaylist(using playerService: PlayerService) async {
        // Two source tracks can match the same video; add it once.
        var seenVideoIds = Set<String>()
        let songs = self.matchedSongs.filter { seenVideoIds.insert($0.videoId).inserted }
        let trimmedTitle = self.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard self.phase == .reviewing, !songs.isEmpty, !trimmedTitle.isEmpty else { return }

        self.phase = .creating
        do {
            let playlist = try await playerService.saveQueueAsPlaylist(
                title: trimmedTitle,
                songs: songs,
                owner: playerService.currentAccountMutationOwner
            )
            self.phase = .finished(playlist)
        } catch is CancellationError {
            self.phase = .reviewing
        } catch {
            self.logger.error("Playlist import failed: \(error.localizedDescription, privacy: .public)")
            self.phase = .failed(error.localizedDescription)
        }
    }

    /// Returns to file selection.
    func reset() {
        self.playlists = []
        self.selectedPlaylistID = nil
        self.title = ""
        self.matches = []
        self.phase = .choosingFile
    }
}
