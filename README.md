# Music Search

An iOS app that lets you search your **Apple Music library in plain language**.
Type what you're after — by mood, language, style, or anything else — and the
app finds matching albums in your library, which you can play or save to a new
playlist.

Example queries:

- "Music in French"
- "Albums that don't have vocals"
- "Albums that are like Brian Eno"
- "New Age albums"

## How it works

1. **Connect to Apple Music** — the opening screen requests library access via
   MusicKit.
2. **Load library** — your saved albums (with artist and genre metadata) are
   read from your library.
3. **AI search** — your query and the library are interpreted by Apple's
   **on-device language model** (the Foundation Models framework). The model
   runs privately on-device and selects the albums that match, using its own
   knowledge of artists, genres, languages, and moods. The library is sent to
   the model in batches to fit its context window.
4. **Results** — matches appear in a grid with a short reason for each. Tap an
   album to play it, or create an Apple Music playlist from all results.

If the on-device model isn't available (older device, or Apple Intelligence
turned off), the app falls back to simple keyword matching so it still works.

## Project layout

```
MusicSearch/
  MusicSearchApp.swift            App entry point
  Models/
    LibraryAlbum.swift            Sendable wrapper around a MusicKit Album
    SearchResult.swift            A matched album + relevance + reason
  Services/
    MusicLibraryService.swift     Reads albums from the user's library
    AISearchService.swift         Search protocol + implementation factory
    FoundationModelSearchService  On-device Foundation Models search
    LocalSearchService.swift      Keyword fallback
    PlaybackService.swift         Play albums / create playlists
  ViewModels/
    AppModel.swift                Authorization + loaded library
    SearchViewModel.swift         Query, progress, results
  Views/
    RootView.swift                Routes Connect vs. Search
    ConnectView.swift             "Connect to Apple Music" screen
    SearchView.swift              Search box + results grid
    AlbumGridItem.swift           Result cell
  Support/
    Array+Chunked.swift
  Assets.xcassets/
```

## Requirements & building

- **Xcode 16+** and **iOS 26+** (the Foundation Models framework requires it).
- The on-device model needs an **Apple Intelligence–capable device**. The app
  still builds and runs everywhere; it just uses the keyword fallback when the
  model is unavailable. The model is not available in the Simulator on all
  configurations — test AI search on a supported physical device.
- An **Apple Developer account** and an **Apple Music subscription** for real
  library access and playback.

### Steps

1. Open `MusicSearch.xcodeproj` in Xcode.
2. Select the `MusicSearch` target → Signing & Capabilities, and set your
   development team (the bundle id defaults to `com.example.MusicSearch`).
3. In your [Apple Developer account](https://developer.apple.com/account), make
   sure the **MusicKit** service is enabled for the App ID.
4. Run on a device signed in to an Apple Music account.

The Apple Music usage description (`NSAppleMusicUsageDescription`) is configured
in the target's build settings and merged into the generated `Info.plist`.

## Scope / status

This is the **core flow**: connect → load library → AI search → results, with
tap-to-play and a basic "create playlist from results" action. Playlist editing,
song-level results, caching, and pagination beyond the first 1,000 albums are
follow-ups.
