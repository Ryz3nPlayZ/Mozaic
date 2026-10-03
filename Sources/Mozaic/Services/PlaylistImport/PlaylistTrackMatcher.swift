import Foundation

/// Picks the YouTube Music song that best matches an imported track (ADR-1002).
///
/// Scores song search results on title, artist, and duration, and rejects
/// covers, karaoke, and similar versions the source track didn't ask for.
enum PlaylistTrackMatcher {
    /// Minimum score for a search result to count as a match.
    static let matchThreshold = 0.6

    /// The search query for a track: its core title and primary artist.
    static func searchQuery(for track: ImportedTrack) -> String {
        let title = Self.stripVersionSuffix(track.title)
        guard let artist = track.artists.first else { return title }
        return "\(title) \(artist)"
    }

    /// The best-scoring candidate at or above `matchThreshold`, preferring
    /// earlier (higher-ranked) results on ties.
    static func bestMatch(for track: ImportedTrack, in candidates: [Song]) -> Song? {
        var best: (song: Song, score: Double)?
        for candidate in candidates where candidate.isPlayable {
            let score = Self.score(track, candidate)
            if score >= Self.matchThreshold, score > (best?.score ?? 0) {
                best = (candidate, score)
            }
        }
        return best?.song
    }

    /// A 0–1 similarity score between an imported track and a song.
    static func score(_ track: ImportedTrack, _ song: Song) -> Double {
        let title = Self.titleScore(track.title, song.title)
        let artist = Self.artistScore(track.artists, song.artists.map(\.name))
        let duration = Self.durationScore(track.duration, song.duration)
        var score = 0.5 * title + 0.35 * artist + 0.15 * duration
        if Self.isUnrequestedVariant(source: track.title, candidate: song.title) {
            score -= 0.3
        }
        return max(0, score)
    }

    // MARK: Components

    static func titleScore(_ source: String, _ candidate: String) -> Double {
        let lhs = Self.normalize(Self.stripVersionSuffix(source))
        let rhs = Self.normalize(Self.stripVersionSuffix(candidate))
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        if lhs == rhs { return 1 }
        if lhs.contains(rhs) || rhs.contains(lhs) { return 0.8 }
        return Self.tokenOverlap(lhs, rhs)
    }

    static func artistScore(_ source: [String], _ candidate: [String]) -> Double {
        guard !source.isEmpty else { return 0.5 }
        let lhs = source.map(Self.normalize).filter { !$0.isEmpty }
        let rhs = candidate.map(Self.normalize).filter { !$0.isEmpty }
        guard !rhs.isEmpty else { return 0 }
        for sourceArtist in lhs {
            for candidateArtist in rhs
                where sourceArtist == candidateArtist
                || sourceArtist.contains(candidateArtist)
                || candidateArtist.contains(sourceArtist)
            {
                return 1
            }
        }
        return Self.tokenOverlap(lhs.joined(separator: " "), rhs.joined(separator: " "))
    }

    static func durationScore(_ source: TimeInterval?, _ candidate: TimeInterval?) -> Double {
        guard let source, let candidate else { return 0.5 }
        switch abs(source - candidate) {
        case ...3: return 1
        case ...10: return 0.7
        case ...30: return 0.3
        default: return 0
        }
    }

    // MARK: Normalization

    private static let variantWords = [
        "karaoke", "cover", "instrumental", "8d", "slowed", "sped up", "nightcore", "reverb",
    ]

    /// Whether the candidate is a version (cover, karaoke, …) the source title
    /// doesn't mention.
    static func isUnrequestedVariant(source: String, candidate: String) -> Bool {
        let source = source.lowercased()
        let candidate = candidate.lowercased()
        return Self.variantWords.contains { candidate.contains($0) && !source.contains($0) }
    }

    /// Drops Spotify-style suffixes such as " - Remastered 2011" or
    /// " (feat. Someone)" that YouTube Music titles usually omit.
    static func stripVersionSuffix(_ title: String) -> String {
        var result = title
        if let range = result.range(of: " - ") {
            result = String(result[..<range.lowerBound])
        }
        result = result.replacingOccurrences(
            of: #"\s*[\(\[](feat\.?|ft\.?|with|from|remaster|live|radio edit|mono|stereo)[^\)\]]*[\)\]]"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Lowercases, folds diacritics, and keeps only letters, digits, and single spaces.
    static func normalize(_ value: String) -> String {
        let folded = value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "&", with: " and ")
        let scalars = folded.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(scalars).split(separator: " ").joined(separator: " ")
    }

    private static func tokenOverlap(_ lhs: String, _ rhs: String) -> Double {
        let lhsTokens = Set(lhs.split(separator: " "))
        let rhsTokens = Set(rhs.split(separator: " "))
        let union = lhsTokens.union(rhsTokens)
        guard !union.isEmpty else { return 0 }
        return Double(lhsTokens.intersection(rhsTokens).count) / Double(union.count)
    }
}
