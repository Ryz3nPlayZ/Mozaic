import Foundation

// MARK: - ImportedTrack

/// A track read from another service's playlist export, before it is matched
/// to a YouTube Music song (ADR-1002).
struct ImportedTrack: Hashable, Sendable {
    let title: String
    let artists: [String]
    let album: String?
    /// Duration in seconds, when the export includes one.
    let duration: TimeInterval?

    init(title: String, artists: [String], album: String? = nil, duration: TimeInterval? = nil) {
        self.title = title
        self.artists = artists
        self.album = album
        self.duration = duration
    }
}

// MARK: - ImportedPlaylist

/// A named list of tracks read from an export file.
struct ImportedPlaylist: Hashable, Sendable, Identifiable {
    /// Position in the export file. Names aren't unique: Spotify allows
    /// several playlists with the same name.
    var id = 0
    let name: String
    let tracks: [ImportedTrack]
}

// MARK: - PlaylistImportError

enum PlaylistImportError: LocalizedError, Equatable {
    case unreadable
    case noTracks

    var errorDescription: String? {
        switch self {
        case .unreadable:
            String(localized: "This file isn't a playlist export Mozaic can read.")
        case .noTracks:
            String(localized: "No songs were found in this playlist.")
        }
    }
}

// MARK: - PlaylistImportParser

/// Reads playlists exported from Spotify and similar services.
///
/// Supported inputs:
/// - CSV from Exportify, TuneMyMusic, or Soundiiz (a header row naming the
///   track and artist columns).
/// - JSON from Spotify's account data download (`Playlist*.json`,
///   `YourLibrary.json`).
/// - Plain text with one `Artist - Title` per line.
enum PlaylistImportParser {
    /// Parses an export file, using its extension and contents to pick a format.
    static func parse(data: Data, fileName: String) throws -> [ImportedPlaylist] {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else {
            throw PlaylistImportError.unreadable
        }
        let fallbackName = Self.playlistName(fromFileName: fileName)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines.union(Self.byteOrderMark))

        let playlists: [ImportedPlaylist]
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            playlists = try Self.parseSpotifyJSON(data: Data(trimmed.utf8), fallbackName: fallbackName)
        } else if fileName.lowercased().hasSuffix(".csv") || Self.looksLikeCSV(trimmed) {
            playlists = [ImportedPlaylist(name: fallbackName, tracks: try Self.parseCSV(trimmed))]
        } else {
            playlists = [ImportedPlaylist(name: fallbackName, tracks: Self.parseText(trimmed))]
        }

        let nonEmpty = playlists.filter { !$0.tracks.isEmpty }
        guard !nonEmpty.isEmpty else { throw PlaylistImportError.noTracks }
        return nonEmpty.enumerated().map { index, playlist in
            var playlist = playlist
            playlist.id = index
            return playlist
        }
    }

    // MARK: CSV

    private static let titleColumns = ["track name", "name", "title", "song", "track", "song name"]
    private static let artistColumns = ["artist name(s)", "artist names", "artist name", "artist", "artists"]
    private static let albumColumns = ["album name", "album", "album title"]
    private static let durationColumns = ["duration (ms)", "duration_ms", "duration"]

    /// Parses a CSV export with a header row.
    static func parseCSV(_ text: String) throws -> [ImportedTrack] {
        let rows = Self.csvRows(text)
        guard let header = rows.first else { throw PlaylistImportError.noTracks }
        let columns = header.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }

        func index(of candidates: [String]) -> Int? {
            for candidate in candidates {
                if let index = columns.firstIndex(of: candidate) {
                    return index
                }
            }
            return nil
        }

        guard let titleIndex = index(of: Self.titleColumns) else {
            throw PlaylistImportError.unreadable
        }
        let artistIndex = index(of: Self.artistColumns)
        let albumIndex = index(of: Self.albumColumns)
        let durationIndex = index(of: Self.durationColumns)
        let durationIsMilliseconds = durationIndex.map { columns[$0].contains("ms") } ?? false

        return rows.dropFirst().compactMap { row in
            func field(_ index: Int?) -> String? {
                guard let index, index < row.count else { return nil }
                let value = row[index].trimmingCharacters(in: .whitespaces)
                return value.isEmpty ? nil : value
            }
            guard let title = field(titleIndex) else { return nil }
            return ImportedTrack(
                title: title,
                artists: Self.splitArtists(field(artistIndex)),
                album: field(albumIndex),
                duration: Self.duration(field(durationIndex), milliseconds: durationIsMilliseconds)
            )
        }
    }

    /// Splits CSV text into rows of fields, honoring quoted fields that contain
    /// commas, escaped quotes, or line breaks.
    static func csvRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.unicodeScalars.makeIterator()
        var pending: Unicode.Scalar? = iterator.next()

        while let scalar = pending {
            pending = iterator.next()
            if inQuotes {
                if scalar == "\"" {
                    if pending == "\"" {
                        field.unicodeScalars.append("\"")
                        pending = iterator.next()
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.unicodeScalars.append(scalar)
                }
                continue
            }
            switch scalar {
            case "\"":
                inQuotes = true
            case ",":
                row.append(field)
                field = ""
            case "\r":
                if pending == "\n" { pending = iterator.next() }
                fallthrough
            case "\n":
                row.append(field)
                if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
                row = []
                field = ""
            default:
                field.unicodeScalars.append(scalar)
            }
        }
        row.append(field)
        if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
        return rows
    }

    private static func looksLikeCSV(_ text: String) -> Bool {
        guard let firstLine = text.split(whereSeparator: \.isNewline).first?.lowercased() else { return false }
        return firstLine.contains(",") && Self.titleColumns.contains { firstLine.contains($0) }
    }

    // MARK: Spotify JSON

    private struct SpotifyPlaylistsFile: Decodable {
        struct Playlist: Decodable {
            let name: String
            let items: [Item]?
        }

        struct Item: Decodable {
            let track: Track?
        }

        struct Track: Decodable {
            let trackName: String?
            let artistName: String?
            let albumName: String?
        }

        let playlists: [Playlist]
    }

    private struct SpotifyLibraryFile: Decodable {
        struct Track: Decodable {
            let artist: String?
            let album: String?
            let track: String?
        }

        let tracks: [Track]
    }

    /// Parses Spotify's account data download (`Playlist1.json` or `YourLibrary.json`).
    static func parseSpotifyJSON(data: Data, fallbackName: String) throws -> [ImportedPlaylist] {
        let decoder = JSONDecoder()
        if let file = try? decoder.decode(SpotifyPlaylistsFile.self, from: data) {
            return file.playlists.map { playlist in
                let tracks = (playlist.items ?? []).compactMap { item -> ImportedTrack? in
                    guard let track = item.track, let title = Self.nonEmpty(track.trackName) else { return nil }
                    return ImportedTrack(
                        title: title,
                        artists: Self.splitArtists(track.artistName),
                        album: Self.nonEmpty(track.albumName)
                    )
                }
                return ImportedPlaylist(name: playlist.name, tracks: tracks)
            }
        }
        if let file = try? decoder.decode(SpotifyLibraryFile.self, from: data) {
            let tracks = file.tracks.compactMap { track -> ImportedTrack? in
                guard let title = Self.nonEmpty(track.track) else { return nil }
                return ImportedTrack(
                    title: title,
                    artists: Self.splitArtists(track.artist),
                    album: Self.nonEmpty(track.album)
                )
            }
            return [ImportedPlaylist(name: String(localized: "Liked Songs"), tracks: tracks)]
        }
        throw PlaylistImportError.unreadable
    }

    // MARK: Plain text

    private static let textSeparators = [" - ", " – ", " — "]

    /// Parses one `Artist - Title` per line. Lines without a separator are
    /// treated as a title on its own.
    static func parseText(_ text: String) -> [ImportedTrack] {
        text.split(whereSeparator: \.isNewline).compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { return nil }
            for separator in Self.textSeparators {
                if let range = line.range(of: separator) {
                    let artist = line[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
                    let title = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
                    guard !title.isEmpty else { break }
                    return ImportedTrack(title: title, artists: Self.splitArtists(artist))
                }
            }
            return ImportedTrack(title: line, artists: [])
        }
    }

    // MARK: Helpers

    private static let byteOrderMark = CharacterSet(charactersIn: "\u{FEFF}")

    static func playlistName(fromFileName fileName: String) -> String {
        let name = (fileName as NSString).deletingPathExtension
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? String(localized: "Imported Playlist") : name
    }

    private static func splitArtists(_ value: String?) -> [String] {
        guard let value else { return [] }
        return value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func duration(_ value: String?, milliseconds: Bool) -> TimeInterval? {
        guard let value else { return nil }
        if let number = Double(value) {
            return milliseconds || number > 10000 ? number / 1000 : number
        }
        // "m:ss" or "h:mm:ss"
        let parts = value.split(separator: ":").compactMap { Double($0) }
        guard parts.count >= 2 else { return nil }
        return parts.reduce(0) { $0 * 60 + $1 }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        return value
    }
}
