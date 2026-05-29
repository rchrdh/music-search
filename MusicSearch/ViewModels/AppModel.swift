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
        defer { isLoadingLibrary = false }
        do {
            albums = try await MusicLibraryService.fetchAlbums()
        } catch {
            libraryError = error.localizedDescription
        }
    }
}
