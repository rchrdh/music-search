# musicsearch-eval

A command-line harness for refining search/recommendation quality **off-device**.
It runs the exact same engine the iOS app uses (`MusicSearch/Engine`, compiled
here as the `MusicSearchCore` package) against a JSON list of albums, hitting the
real Last.fm and MusicBrainz APIs — so you can tweak scoring or the parser and
see results in seconds, without a device or Xcode rebuild.

## Run

From the repo root (needs the Swift toolchain that ships with Xcode):

```sh
export LASTFM_API_KEY=your_key_here

# Against the built-in sample set:
swift run musicsearch-eval "Albums that are like Brian Eno"
swift run musicsearch-eval "New Age albums"

# Language queries: add --language to fetch MusicBrainz language (slow, ~1/sec).
swift run musicsearch-eval "Music in French" --language

# Against your real library (export it from the app — see below):
swift run musicsearch-eval "Music in French" --albums ~/Downloads/library-export.json --language --limit 50
```

Flags: `--albums <path>`, `--limit <n>`, `--language`, `--verbose`.

## Export your real library

In the app's start screen, tap **Export library (JSON)** and save/AirDrop the
file to your Mac, then pass it with `--albums`.

## Offline tests

The scoring logic is pure and unit-tested without network:

```sh
swift test
```
