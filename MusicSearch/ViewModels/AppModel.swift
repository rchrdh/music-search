import Foundation
import Observation
import MusicKit

/// App-wide state: Apple Music authorization and the loaded library.
@MainActor
@Observable
final class AppModel {
    var authorizationStatus: MusicAuthorization.Status = MusicAuthorization.currentStatus
    var albums: [LibraryAlbum] = []
    var isLoadingLibrary = false
    var libraryError: String?

    /// Progress (0...1) of background metadata enrichment, and whether it's running.
    var enrichmentProgress: Double = 0
    var isEnriching = false

    var isAuthorized: Bool { authorizationStatus == .authorized }

    /// Re-reads the current authorization status (e.g. on launch / foreground).
    func refreshAuthorizationStatus() async {
        authorizationStatus = MusicAuthorization.currentStatus
        if isAuthorized && albums.isEmpty && !isLoadingLibrary {
            await loadLibrary()
        }
    }

    /// Prompts the user to connect to Apple Music, then loads their library.
    func connect() async {
        let status = await MusicAuthorization.request()
        authorizationStatus = status
        if status == .authorized {
            await loadLibrary()
        }
    }

    func loadLibrary() async {
        isLoadingLibrary = true
        libraryError = nil
        do {
            albums = try await MusicLibraryService.fetchAlbums()
        } catch {
            libraryError = error.localizedDescription
        }
        isLoadingLibrary = false

        // Enrich in the background so searches can use real metadata. Searches
        // still work while this runs; results just improve as it fills in.
        await enrichLibrary()
    }

    private func enrichLibrary() async {
        guard let key = Secrets.lastFMAPIKey, !albums.isEmpty else { return }
        isEnriching = true
        enrichmentProgress = 0
        defer { isEnriching = false }

        let service = MetadataEnrichmentService(client: LastFMClient(apiKey: key), store: .shared)

        // Bridge the @Sendable progress callback back onto the main actor.
        let (stream, continuation) = AsyncStream<Double>.makeStream()
        let consumer = Task { @MainActor in
            for await value in stream { self.enrichmentProgress = value }
        }
        defer { consumer.cancel() }

        await service.enrich(albums) { continuation.yield($0) }
        continuation.finish()
    }
}
