import Foundation
import Testing
@testable import Mozaic

// MARK: - PlaylistImportParserTests

@Suite("PlaylistImportParser")
struct PlaylistImportParserTests {
    @Test("Parses an Exportify CSV with quoted fields and millisecond durations")
    func parsesExportifyCSV() throws {
        let csv = "\u{FEFF}" + #"""
        Track URI,Track Name,Album Name,Artist Name(s),Release Date,Duration (ms)
        spotify:track:1,"Bohemian Rhapsody - Remastered 2011",A Night at the Opera,Queen,1975-11-21,354320
        spotify:track:2,"Under Pressure","Hot Space","Queen, David Bowie",1982-05-21,248440
        spotify:track:3,"Say ""Hello""",Album,Artist,2020,180000
        """#
        let playlists = try PlaylistImportParser.parse(data: Data(csv.utf8), fileName: "Road_Trip.csv")

        #expect(playlists.count == 1)
        #expect(playlists[0].name == "Road Trip")
        let tracks = playlists[0].tracks
        #expect(tracks.count == 3)
        #expect(tracks[0] == ImportedTrack(
            title: "Bohemian Rhapsody - Remastered 2011",
            artists: ["Queen"],
            album: "A Night at the Opera",
            duration: 354.32
        ))
        #expect(tracks[1].artists == ["Queen", "David Bowie"])
        #expect(tracks[2].title == "Say \"Hello\"")
    }

    @Test("Parses a TuneMyMusic CSV with CRLF line endings")
    func parsesTuneMyMusicCSV() throws {
        let csv = "Track name,Artist name,Album,Playlist name\r\nYellow,Coldplay,Parachutes,Mix\r\n\r\n"
        let tracks = try PlaylistImportParser.parseCSV(csv)
        #expect(tracks == [ImportedTrack(title: "Yellow", artists: ["Coldplay"], album: "Parachutes")])
    }

    @Test("Rejects a CSV without a title column")
    func rejectsCSVWithoutTitle() {
        #expect(throws: PlaylistImportError.unreadable) {
            try PlaylistImportParser.parseCSV("Foo,Bar\n1,2")
        }
    }

    @Test("Parses every playlist in a Spotify account data export")
    func parsesSpotifyPlaylistJSON() throws {
        let json = """
        {"playlists": [
          {"name": "Chill", "lastModifiedDate": "2024-01-01", "items": [
            {"track": {"trackName": "Holocene", "artistName": "Bon Iver", "albumName": "Bon Iver", "trackUri": "spotify:track:x"}},
            {"track": null, "episode": {"episodeName": "A podcast"}}
          ]},
          {"name": "Empty", "items": []}
        ]}
        """
        let playlists = try PlaylistImportParser.parse(data: Data(json.utf8), fileName: "Playlist1.json")

        #expect(playlists.map(\.name) == ["Chill"])
        #expect(playlists.map(\.id) == [0])
        #expect(playlists[0].tracks == [ImportedTrack(title: "Holocene", artists: ["Bon Iver"], album: "Bon Iver")])
    }

    @Test("Gives playlists with the same name distinct identities")
    func duplicateNamesGetDistinctIDs() throws {
        let json = """
        {"playlists": [
          {"name": "Mix", "items": [{"track": {"trackName": "A", "artistName": "X"}}]},
          {"name": "Mix", "items": [{"track": {"trackName": "B", "artistName": "Y"}}]}
        ]}
        """
        let playlists = try PlaylistImportParser.parse(data: Data(json.utf8), fileName: "Playlist1.json")
        #expect(Set(playlists.map(\.id)).count == 2)
    }

    @Test("Parses Spotify's saved library export")
    func parsesSpotifyLibraryJSON() throws {
        let json = """
        {"tracks": [{"artist": "Daft Punk", "album": "Discovery", "track": "One More Time", "uri": "spotify:track:y"}], "albums": []}
        """
        let playlists = try PlaylistImportParser.parse(data: Data(json.utf8), fileName: "YourLibrary.json")
        #expect(playlists.count == 1)
        #expect(playlists[0].tracks == [ImportedTrack(title: "One More Time", artists: ["Daft Punk"], album: "Discovery")])
    }

    @Test("Parses Artist - Title text lines")
    func parsesText() {
        let tracks = PlaylistImportParser.parseText("""
        # My mix
        Radiohead - Weird Fishes/Arpeggi
        Beyoncé – Halo

        Just A Title
        """)
        #expect(tracks == [
            ImportedTrack(title: "Weird Fishes/Arpeggi", artists: ["Radiohead"]),
            ImportedTrack(title: "Halo", artists: ["Beyoncé"]),
            ImportedTrack(title: "Just A Title", artists: []),
        ])
    }

    @Test("Throws when a file has no tracks")
    func throwsWhenEmpty() {
        #expect(throws: PlaylistImportError.noTracks) {
            try PlaylistImportParser.parse(data: Data("Track Name,Artist\n".utf8), fileName: "empty.csv")
        }
    }
}

// MARK: - PlaylistTrackMatcherTests

@Suite("PlaylistTrackMatcher")
struct PlaylistTrackMatcherTests {
    private static func song(_ title: String, _ artist: String, duration: TimeInterval? = nil, id: String) -> Song {
        Song(
            id: id,
            title: title,
            artists: [Artist.inline(name: artist, namespace: "import-test")],
            duration: duration,
            videoId: id
        )
    }

    @Test("Search query drops Spotify version suffixes and uses the primary artist")
    func searchQuery() {
        let track = ImportedTrack(title: "Bohemian Rhapsody - Remastered 2011", artists: ["Queen", "Someone"])
        #expect(PlaylistTrackMatcher.searchQuery(for: track) == "Bohemian Rhapsody Queen")
        #expect(PlaylistTrackMatcher.stripVersionSuffix("Stay (feat. Justin Bieber)") == "Stay")
        #expect(PlaylistTrackMatcher.stripVersionSuffix("Song (Acoustic)") == "Song (Acoustic)")
    }

    @Test("Normalizes case, diacritics, and punctuation")
    func normalize() {
        #expect(PlaylistTrackMatcher.normalize("Beyoncé & JAY-Z!") == "beyonce and jay z")
    }

    @Test("Picks the matching artist and duration over a higher-ranked cover")
    func picksOriginalOverCover() {
        let track = ImportedTrack(title: "Halo", artists: ["Beyoncé"], duration: 261)
        let candidates = [
            Self.song("Halo (Karaoke Version)", "Sing King", duration: 262, id: "karaoke"),
            Self.song("Halo", "Some Cover Band", duration: 230, id: "cover"),
            Self.song("Halo", "Beyonce", duration: 262, id: "original"),
        ]
        #expect(PlaylistTrackMatcher.bestMatch(for: track, in: candidates)?.videoId == "original")
    }

    @Test("Returns nil when nothing is close enough")
    func rejectsPoorMatches() {
        let track = ImportedTrack(title: "Weird Fishes", artists: ["Radiohead"], duration: 318)
        let candidates = [Self.song("Fish Tacos", "Chef Band", duration: 120, id: "nope")]
        #expect(PlaylistTrackMatcher.bestMatch(for: track, in: candidates) == nil)
    }

    @Test("Prefers the earlier result on a tie")
    func prefersEarlierOnTie() {
        let track = ImportedTrack(title: "Yellow", artists: ["Coldplay"])
        let candidates = [
            Self.song("Yellow", "Coldplay", id: "first"),
            Self.song("Yellow", "Coldplay", id: "second"),
        ]
        #expect(PlaylistTrackMatcher.bestMatch(for: track, in: candidates)?.videoId == "first")
    }
}

// MARK: - PlaylistImportViewModelTests

@Suite("PlaylistImportViewModel", .tags(.viewModel))
@MainActor
struct PlaylistImportViewModelTests {
    @Test("Loading a file selects its first playlist and names the import after it")
    func loadSelectsFirstPlaylist() {
        let viewModel = PlaylistImportViewModel(client: MockYTMusicClient())
        viewModel.load(data: Data("Yellow,x\n".utf8), fileName: "bad.csv")
        #expect(viewModel.phase == .failed(PlaylistImportError.unreadable.localizedDescription))

        viewModel.reset()
        viewModel.load(data: Data("Coldplay - Yellow\n".utf8), fileName: "Favorites.txt")
        #expect(viewModel.phase == .ready)
        #expect(viewModel.title == "Favorites")
        #expect(viewModel.selectedPlaylist?.tracks.count == 1)
    }

    @Test("Matching searches every track and separates unmatched ones")
    func matchingSearchesEveryTrack() async {
        let client = MockYTMusicClient()
        client.songsSearchResponse = SearchResponse(
            items: [.song(Song(
                id: "yellow",
                title: "Yellow",
                artists: [Artist.inline(name: "Coldplay", namespace: "import-test")],
                videoId: "yellow"
            ))],
            continuationToken: nil
        )
        let viewModel = PlaylistImportViewModel(client: client)
        viewModel.load(data: Data("Coldplay - Yellow\nNobody - Missing Song\n".utf8), fileName: "Mix.txt")

        await viewModel.matchTracks()

        #expect(viewModel.phase == .reviewing)
        #expect(client.searchQueries.sorted() == ["Missing Song Nobody", "Yellow Coldplay"])
        #expect(viewModel.matchedSongs.map(\.videoId) == ["yellow"])
        #expect(viewModel.unmatchedTracks == [ImportedTrack(title: "Missing Song", artists: ["Nobody"])])
    }

    @Test("Matching fails when every search fails")
    func matchingFailsWhenSearchFails() async {
        let client = MockYTMusicClient()
        client.shouldThrowError = YTMusicError.authExpired
        let viewModel = PlaylistImportViewModel(client: client)
        viewModel.load(data: Data("Coldplay - Yellow\n".utf8), fileName: "Mix.txt")

        await viewModel.matchTracks()

        guard case .failed = viewModel.phase else {
            Issue.record("Expected failure, got \(viewModel.phase)")
            return
        }
    }
}
