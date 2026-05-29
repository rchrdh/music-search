import SwiftUI
import MusicKit

/// Main screen: a text box for natural-language queries and a grid of results.
struct SearchView: View {
    @Environment(AppModel.self) private var appModel
    @State private var model = SearchViewModel()

    @State private var showCreatePlaylist = false
    @State private var playlistName = ""
    @State private var statusMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]
    private let suggestions = [
        "Music in French",
        "Albums that don't have vocals",
        "Albums that are like Brian Eno",
        "New Age albums",
    ]

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Music Search")
                .searchableConfig(model: $model, run: runSearch)
                .toolbar { toolbarContent }
                .overlay(alignment: .bottom) { statusBanner }
                .alert("New Playlist", isPresented: $showCreatePlaylist) {
                    TextField("Playlist name", text: $playlistName)
                    Button("Cancel", role: .cancel) {}
                    Button("Create") { createPlaylist() }
                } message: {
                    Text("Create an Apple Music playlist from these \(model.results.count) albums.")
                }
        }
    }

    // MARK: - Content states

    @ViewBuilder
    private var content: some View {
        if appModel.isLoadingLibrary {
            ProgressView("Loading your library…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch model.phase {
            case .idle:
                idleState
            case .error(let message):
                errorState(message)
            case .searching, .results:
                if model.results.isEmpty {
                    if model.phase == .searching {
                        searchingState
                    } else {
                        ContentUnavailableView.search(text: model.trimmedQuery)
                    }
                } else {
                    resultsState
                }
            }
        }
    }

    private var idleState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Try searching for…")
                    .font(.headline)
                ForEach(suggestions, id: \.self) { suggestion in
                    Button {
                        model.query = suggestion
                        runSearch()
                    } label: {
                        Label(suggestion, systemImage: "sparkles")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }

                Text(footnote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
            .padding()
        }
    }

    private var searchingState: some View {
        VStack(spacing: 16) {
            ProgressView(value: model.progress)
                .progressViewStyle(.linear)
                .padding(.horizontal, 40)
            Text("Searching \(appModel.albums.count) albums…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultsState: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(model.results) { result in
                    AlbumGridItem(result: result) { play(result.album) }
                }
            }
            .padding()
        }
        // Live progress bar while more batches are still being searched.
        .safeAreaInset(edge: .top) {
            if model.phase == .searching {
                VStack(spacing: 4) {
                    ProgressView(value: model.progress)
                        .progressViewStyle(.linear)
                    Text("Found \(model.results.count) so far · \(Int(model.progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
            }
        }
    }

    private func errorState(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Search Failed", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") { runSearch() }
        }
    }

    // MARK: - Toolbar / banner

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if model.phase == .results && !model.results.isEmpty {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    playlistName = model.trimmedQuery
                    showCreatePlaylist = true
                } label: {
                    Label("Create Playlist", systemImage: "text.badge.plus")
                }
            }
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        if let statusMessage {
            Text(statusMessage)
                .font(.subheadline)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.thinMaterial, in: Capsule())
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var footnote: String {
        model.usesOnDeviceModel
            ? "Searches run privately on your device using Apple Intelligence."
            : "On-device intelligence isn't available, so searches use keyword matching."
    }

    // MARK: - Actions

    private func runSearch() {
        model.search(in: appModel.albums)
    }

    private func play(_ album: LibraryAlbum) {
        Task {
            do {
                try await PlaybackService.play(album)
            } catch {
                await flash("Couldn't play \(album.title).")
            }
        }
    }

    private func createPlaylist() {
        let name = playlistName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let albums = model.results.map(\.album)
        Task {
            do {
                _ = try await PlaybackService.createPlaylist(named: name, from: albums)
                await flash("Created playlist “\(name)”.")
            } catch {
                await flash("Couldn't create the playlist.")
            }
        }
    }

    @MainActor
    private func flash(_ message: String) async {
        withAnimation { statusMessage = message }
        try? await Task.sleep(for: .seconds(2.5))
        withAnimation { statusMessage = nil }
    }
}

// MARK: - Searchable helper

private extension View {
    /// Wires up the navigation search field to the view model.
    func searchableConfig(model: Binding<SearchViewModel>, run: @escaping () -> Void) -> some View {
        self
            .searchable(
                text: model.query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Describe the music you're looking for"
            )
            .onSubmit(of: .search, run)
    }
}

#Preview {
    SearchView()
        .environment(AppModel())
}
