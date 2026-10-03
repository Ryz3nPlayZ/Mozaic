import SwiftUI
import UniformTypeIdentifiers

/// Imports a Spotify playlist export into a new YouTube Music playlist (ADR-1002).
struct PlaylistImportSheet: View {
    @State var viewModel: PlaylistImportViewModel
    let onOpenPlaylist: (Playlist) -> Void

    @Environment(PlayerService.self) private var playerService
    @Environment(\.dismiss) private var dismiss
    @State private var isChoosingFile = false
    @State private var matchTask: Task<Void, Never>?

    private static let exportifyURL = URL(string: "https://exportify.net")

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(String(localized: "Import Playlist"))
                    .font(.headline)
                Spacer()
                Button {
                    self.dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Close"))
            }
            .padding()

            Divider()

            self.content
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 500, height: 440)
        .fileImporter(
            isPresented: self.$isChoosingFile,
            allowedContentTypes: [.commaSeparatedText, .json, .plainText]
        ) { result in
            if case let .success(url) = result {
                self.viewModel.load(fileURL: url)
            }
        }
        .onDisappear {
            self.matchTask?.cancel()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch self.viewModel.phase {
        case .choosingFile:
            self.chooseFileView
        case .ready:
            self.readyView
        case let .matching(completed, total):
            self.progressView(
                String(localized: "Finding songs on YouTube Music…"),
                detail: String(localized: "\(completed) of \(total)"),
                value: Double(completed),
                total: Double(max(total, 1))
            )
        case .reviewing:
            self.reviewView
        case .creating:
            self.progressView(String(localized: "Creating playlist…"), detail: nil, value: nil, total: 1)
        case let .finished(playlist):
            self.finishedView(playlist)
        case let .failed(message):
            self.failedView(message)
        }
    }

    // MARK: Steps

    private var chooseFileView: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
            Text(String(localized: "Bring a Spotify playlist to YouTube Music"))
                .font(.title3.weight(.semibold))
            Text(String(localized: "Mozaic finds each song on YouTube Music and saves them to a new private playlist in your account, so it shows up everywhere you use YouTube Music."))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button(String(localized: "Choose File…")) {
                self.isChoosingFile = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            VStack(spacing: 4) {
                Text(String(localized: "Export a playlist as CSV with Exportify, or use the JSON files from Spotify's account data download. Text files with one “Artist - Title” per line work too."))
                    .multilineTextAlignment(.center)
                if let url = Self.exportifyURL {
                    Link(String(localized: "Open Exportify"), destination: url)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxHeight: .infinity)
    }

    private var readyView: some View {
        VStack(alignment: .leading, spacing: 16) {
            if self.viewModel.playlists.count > 1 {
                Picker(
                    String(localized: "Playlist"),
                    selection: Binding(
                        get: { self.viewModel.selectedPlaylistID },
                        set: { self.viewModel.selectPlaylist($0) }
                    )
                ) {
                    ForEach(self.viewModel.playlists) { playlist in
                        Text(playlist.name).tag(Optional(playlist.id))
                    }
                }
            }
            self.titleField
            if let playlist = self.viewModel.selectedPlaylist {
                Text(String(localized: "\(playlist.tracks.count) songs"))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack {
                Button(String(localized: "Choose Another File")) {
                    self.viewModel.reset()
                }
                Spacer()
                Button(String(localized: "Find Songs")) {
                    self.matchTask = Task { await self.viewModel.matchTracks() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(self.viewModel.selectedPlaylist == nil)
            }
        }
    }

    private var reviewView: some View {
        VStack(alignment: .leading, spacing: 12) {
            self.titleField
            Text(String(localized: "Found \(self.viewModel.matchedSongs.count) of \(self.viewModel.matches.count) songs."))
                .font(.headline)
            if !self.viewModel.unmatchedTracks.isEmpty {
                Text(String(localized: "Not found on YouTube Music:"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(self.viewModel.unmatchedTracks.enumerated()), id: \.offset) { _, track in
                            Text(Self.label(for: track))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            } else {
                Spacer()
            }
            HStack {
                Button(String(localized: "Start Over")) {
                    self.viewModel.reset()
                }
                Spacer()
                Button(String(localized: "Create Playlist")) {
                    Task { await self.viewModel.createPlaylist(using: self.playerService) }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(
                    self.viewModel.matchedSongs.isEmpty
                        || self.viewModel.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
    }

    private func finishedView(_ playlist: Playlist) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)
            Text(String(localized: "Saved “\(playlist.title)” to your library."))
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            HStack {
                Button(String(localized: "Done")) {
                    self.dismiss()
                }
                Button(String(localized: "Open Playlist")) {
                    self.dismiss()
                    self.onOpenPlaylist(playlist)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func failedView(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
            Text(message)
                .multilineTextAlignment(.center)
            Button(String(localized: "Try Again")) {
                self.viewModel.reset()
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: Components

    private var titleField: some View {
        TextField(
            String(localized: "Playlist Name"),
            text: Binding(
                get: { self.viewModel.title },
                set: { self.viewModel.title = $0 }
            )
        )
        .textFieldStyle(.roundedBorder)
    }

    private func progressView(_ title: String, detail: String?, value: Double?, total: Double) -> some View {
        VStack(spacing: 12) {
            Text(title)
            if let value {
                ProgressView(value: value, total: total)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: 320, maxHeight: .infinity)
    }

    private static func label(for track: ImportedTrack) -> String {
        guard !track.artists.isEmpty else { return track.title }
        return "\(track.artists.joined(separator: ", ")) - \(track.title)"
    }
}
