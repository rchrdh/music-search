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
3. **Enrich** — in the background, each album is enriched once and cached on
   disk (a one-time cost): descriptive **tags from Last.fm** (genre, mood,
   style, "instrumental", etc.) and its precise **release language from
   MusicBrainz** (used for accurate language matching). MusicBrainz lookups are
   serialized to ~1/sec per its rate limit, so the language pass is slow on a
   large library the first time, then instant from cache.
4. **Search** — your query is parsed into structured intent (descriptive tags
   plus any "like *artist*" references). The on-device model is shown the tag
   vocabulary that actually occurs in your library and translates the request
   into it ("chill, no singing" → `chillout`, `downtempo`, `instrumental`), and
   matching is then **exact and local** against the cached metadata. "Like
   *artist*" requests use Last.fm's similar-artists endpoint. This is accurate
   (grounded in real metadata) and fast (no per-album model calls at search
   time).
5. **Results** — matches appear in a grid with a short reason for each. Tap an
   album to play it, or create an Apple Music playlist from all results.

### Search engine selection

The app picks the best available engine automatically:

- **Metadata (Last.fm)** — used when a Last.fm API key is configured. Most
  accurate; see setup below.
- **On-device model** — falls back to Apple's Foundation Models framework when
  no key is set. Private, but the small on-device model is less reliable at
  recalling facts like an album's language.
- **Keyword** — final fallback when neither is available.

## Refining recommendations off-device (`musicsearch-eval`)

The matching engine lives in `MusicSearch/Engine/` — platform-agnostic Swift
shared by the app and a command-line harness. The harness (`eval/`, built via the
root `Package.swift`) runs the same engine against a JSON album list so search
quality can be tuned without a device or Xcode rebuild — and, crucially,
**measured**: a labeled judgments suite reports precision/recall/F1/NDCG per
query, offline and deterministically.

```sh
swift run musicsearch-eval --judgments eval/judgments.json   # the metrics suite (offline)

export LASTFM_API_KEY=your_key_here
swift run musicsearch-eval "Music in French" --albums library-export.json --language
swift test   # offline scorer/grounding/metrics unit tests
```

See `eval/README.md` for details.

## Last.fm setup (for metadata search)

1. Get a free API key: https://www.last.fm/api/account/create
2. Provide it in **either** way:
   - Add a `LASTFM_API_KEY` environment variable to the Run scheme
     (Product → Scheme → Edit Scheme → Run → Arguments → Environment Variables), or
   - Create `MusicSearch/Secrets.plist` with a `LASTFM_API_KEY` string entry.
     This file is git-ignored.

Without a key the app still runs and falls back to the on-device model.

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
