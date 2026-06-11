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
heuristic parser doesn't understand "albums that **don't have** vocals", and
no current engine handles the paraphrase query "calm soothing soundscapes"),
so the aggregate stays an honest picture of quality, not a green dashboard.
Workflow: change the engine → run the suite → compare aggregates → keep or
revert.

## Engines: metadata vs embeddings (A/B)

The harness can run the same suite under three interchangeable rankers:

- **`metadata`** (default) — what the app ships: grounded tag matches,
  confirmed-language gating, similar-artist lists.
- **`embedding`** — pure cosine similarity between a query vector and
  precomputed album vectors (`eval/embeddings.json`), retrieval = everything
  above `--threshold` (default 0.5, chosen by sweeping this suite).
- **`hybrid`** — metadata's hard gates stay hard (reference-artist exclusion,
  confirmed language mismatch); cosine similarity widens retrieval on
  descriptive queries and refines rank order everywhere. On relational
  ("like X") queries cosine never adds retrieval — artist similarity is a
  relation between artists, not a property of an album's text, and letting
  embeddings widen retrieval there measurably pulled in junk.

```sh
swift run musicsearch-eval --judgments eval/judgments.json --compare
swift run musicsearch-eval --judgments eval/judgments.json --engine embedding
swift run musicsearch-eval "Jazz albums" --engine embedding --albums eval/fixtures.json
```

### Results on the committed suite (8 cases, 42 albums)

Vectors: spaCy `en_core_web_md` static word vectors, averaged over content
words (see *Regenerating embeddings* below).

| engine    | precision | recall | F1   | NDCG | forbidden hits |
|-----------|-----------|--------|------|------|----------------|
| metadata  | 0.65      | 0.74   | 0.68 | 0.73 | 0              |
| embedding | 0.43      | 0.46   | 0.44 | 0.46 | 6              |
| hybrid    | 0.65      | 0.74   | 0.68 | 0.74 | 1              |

What the per-query numbers say:

- **Embeddings alone lose, badly.** They cannot express artist similarity
  ("like Brian Eno": F1 0.07 vs metadata's 0.97 — the expected albums score
  *below* the rest, because the relation lives in a similarity graph, not in
  any album's text), negation ("no vocals": 0.00), or sung language
  ("Music in French": 0.55 with 2 forbidden hits vs 1.00 clean).
- **Embeddings win on descriptive genre/mood queries.** "Jazz albums" F1 1.00
  vs 0.67, "Ambient albums" 0.90 vs 0.83 — cosine cleanly separates the real
  jazz/ambient records where tag matching drags in jazz-adjacent strays.
- **Hybrid keeps metadata's precision and inherits the ranking win** (NDCG
  0.74 vs 0.73; it ranks the true jazz albums above the strays even when it
  retrieves the same set). Its one forbidden hit is the paraphrase case below.
- **The paraphrase case ("calm soothing soundscapes") is everyone's gap.**
  Metadata retrieves nothing (no query word grounds into the tag vocabulary —
  this is the query class embeddings exist for). But *static word vectors*
  fail it too: their top hit is Beyoncé's *Lemonade*. Averaged word vectors
  are not sentence understanding.

**Verdict:** with this class of embedding, don't replace the metadata engine —
keep it (or hybrid, which strictly dominates on rank order) and treat
embeddings as a rank-refiner, never a gate-replacer. The open question is
whether a contrastively-trained sentence encoder (e.g. a small
sentence-transformers model, or `NLEmbedding` on-device) flips the paraphrase
case without breaking the others; the format below makes that a drop-in test.

### What a real library adds (4845-track export, 3615 albums)

Running the same comparison against a real export — curated judgments, baked
tags — surfaced things the 42-album fixtures structurally cannot:

- **Set-based retrieval doesn't scale.** "One matched tag = retrieved" returns
  hundreds of albums when the vocabulary is real ("Japanese city pop" → 730,
  because "pop" grounds into every pop-ish tag). Score with `--top <k>`
  (precision/recall at the cutoff users actually see) on big libraries.
- **The scorer doesn't weight tag specificity.** A "desert blues" query ranks
  an album tagged `blues` level with one tagged `tuareg` — flat 2 points per
  matched tag, ties broken by library order. The biggest open quality lever.
- **Embeddings earn their keep on niche descriptive queries** ("Japanese city
  pop": embedding NDCG@20 0.52 vs metadata 0.00) and still lose relational
  ones — same shape as the fixture verdict, only amplified.
- **Real data finds real bugs**: junk one-letter tags, function words
  grounding into "rare groove"/"cabaret", and collaboration credits ("Brian
  Eno & Harold Budd") slipping past the reference-artist exclusion were all
  invisible on the fixtures.

### Regenerating embeddings

`eval/embeddings.json` is model-agnostic: `{model, albums: {id: [Double]},
queries: {text: [Double]}}`, L2-normalized. To rebuild it (or try a different
encoder — only this script would change):

```sh
pip install spacy && python -m spacy download en_core_web_md
python3 scripts/generate-embeddings.py            # fixtures + judgments queries
python3 scripts/generate-embeddings.py --query "some new query"
```

Note: the eval precomputes query vectors, so the comparison runs offline and
deterministically. Shipping an embedding ranker in the app would additionally
need an on-device query encoder (`NLEmbedding.sentenceEmbedding` on Apple
platforms); the album-side index could be precomputed exactly like this.

To eval against your **real library**, export it (from the app, or from
Apple Music on macOS via File → Library → Export Library… plus
`scripts/applemusic-to-eval.py` — album IDs are a stable hash of
artist+album, so they survive re-exports), bake tags into it once, then run
suites offline against the baked file:

```sh
python3 scripts/applemusic-to-eval.py ~/Music/Library.xml > my-library.json
export LASTFM_API_KEY=your_key_here
swift run musicsearch-eval --bake my-library-tagged.json --albums my-library.json
swift run musicsearch-eval --judgments my-judgments.json --albums my-library-tagged.json
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
