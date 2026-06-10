# musicsearch-eval

A command-line harness for refining search/recommendation quality **off-device**.
It runs the exact same engine the iOS app uses (`MusicSearch/Engine`, compiled
here as the `MusicSearchCore` package) — so you can tweak scoring or the parser
and see results in seconds, without a device or Xcode rebuild.

## Judgments mode (the eval that actually measures)

`eval/judgments.json` is a labeled suite: each case is a query plus the album
IDs a good recommender **should** return (`expected`) and **must not** return
(`forbidden`). The harness runs every case and reports precision, recall, F1,
and NDCG per query and in aggregate — so a scoring or parser change is a
measurable diff, not a vibe:

```sh
swift run musicsearch-eval --judgments eval/judgments.json
```

This runs **fully offline** (no API key): the album set it uses,
`eval/fixtures.json`, carries baked `tags` and `language` fields, and the
judgments file carries the `similarArtists` lists that "like X" queries need.
Deterministic input → deterministic metrics → comparable across runs.

The committed suite intentionally includes known engine gaps (e.g. the
heuristic parser doesn't understand "albums that **don't have** vocals"), so
the aggregate stays an honest picture of quality, not a green dashboard.
Workflow: change the engine → run the suite → compare aggregates → keep or
revert.

To eval against your **real library**, export it from the app, convert
judgments-worthy queries you care about into cases (IDs come from the export),
and pass `--albums`:

```sh
export LASTFM_API_KEY=your_key_here   # needed: exports have no baked tags
swift run musicsearch-eval --judgments my-judgments.json --albums library-export.json
```

## Single-query mode

Run one query and inspect the ranked results, including how the raw query
words were grounded into the library's tag vocabulary:

```sh
# Offline, against the baked fixture set:
swift run musicsearch-eval "New Age albums" --albums eval/fixtures.json

# Live, against the un-tagged sample set or a library export:
export LASTFM_API_KEY=your_key_here
swift run musicsearch-eval "Albums that are like Brian Eno"
swift run musicsearch-eval "Music in French" --albums library-export.json --language --limit 50
```

Flags: `--albums <path>`, `--limit <n>`, `--language` (MusicBrainz lookups,
~1/sec, only for candidate albums without a baked language), `--verbose`.
`LASTFM_API_KEY` is required only when something must actually be fetched.

## Export your real library

In the app's start screen, tap **Export library (JSON)** and save/AirDrop the
file to your Mac, then pass it with `--albums`.

## Offline tests

The scoring, grounding, and metrics logic is pure and unit-tested without
network:

```sh
swift test
```
