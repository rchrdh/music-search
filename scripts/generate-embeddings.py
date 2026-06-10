#!/usr/bin/env python3
"""Precompute album + query embeddings for the eval harness.

Embeds every album in an albums JSON file (title/artist/genres/tags) and every
query in a judgments file into one vector table, written as JSON that the Swift
side (EmbeddingIndex) loads. Vectors are L2-normalized, so cosine similarity is
a plain dot product.

The default model is spaCy's en_core_web_md (300-d static word vectors,
averaged over content words). That is deliberately the simplest thing that is
still a real embedding: good enough to answer "do embeddings beat the metadata
scorer on this suite?", and the JSON format is model-agnostic — swap in a
sentence-transformer here and nothing downstream changes.

Usage:
    pip install spacy && python -m spacy download en_core_web_md
    python3 scripts/generate-embeddings.py \
        --albums eval/fixtures.json \
        --judgments eval/judgments.json \
        --out eval/embeddings.json \
        [--query "extra query to embed"]...
"""

import argparse
import json
import sys

# Words that appear in nearly every music query/document and carry no signal
# for distinguishing albums; spaCy's stop list handles the generic ones.
DOMAIN_STOPWORDS = {"album", "albums", "music", "song", "songs", "record", "records", "lp"}


def load_model(name):
    import spacy

    try:
        return spacy.load(name)
    except OSError:
        sys.exit(f"error: spaCy model '{name}' not installed — run: python -m spacy download {name}")


def embed(nlp, text):
    """Mean of the vectors of content tokens, L2-normalized. None if no token
    has a vector (e.g. all proper nouns outside the model's vocabulary)."""
    doc = nlp(text.lower())
    vectors = [
        t.vector
        for t in doc
        if t.has_vector and not t.is_stop and not t.is_punct and t.text not in DOMAIN_STOPWORDS
    ]
    if not vectors:
        return None
    import numpy as np

    mean = np.mean(vectors, axis=0)
    norm = np.linalg.norm(mean)
    if norm == 0:
        return None
    return [round(float(x), 5) for x in mean / norm]


def album_text(album):
    parts = [album.get("title", ""), album.get("artist", "")]
    parts += album.get("genres") or []
    parts += album.get("tags") or []
    return ". ".join(p for p in parts if p)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--albums", default="eval/fixtures.json")
    parser.add_argument("--judgments", default="eval/judgments.json")
    parser.add_argument("--out", default="eval/embeddings.json")
    parser.add_argument("--model", default="en_core_web_md")
    parser.add_argument("--query", action="append", default=[], help="extra query to embed (repeatable)")
    args = parser.parse_args()

    nlp = load_model(args.model)

    with open(args.albums) as f:
        albums = json.load(f)
    queries = list(args.query)
    if args.judgments:
        with open(args.judgments) as f:
            queries += [case["query"] for case in json.load(f)["cases"]]

    album_vectors = {}
    for album in albums:
        vector = embed(nlp, album_text(album))
        if vector is None:
            print(f"warning: no vector for album {album['id']} ({album.get('title')})", file=sys.stderr)
            continue
        album_vectors[album["id"]] = vector

    query_vectors = {}
    for query in queries:
        vector = embed(nlp, query)
        if vector is None:
            print(f"warning: no vector for query: {query}", file=sys.stderr)
            continue
        query_vectors[query] = vector

    out = {"model": f"spacy/{args.model}", "albums": album_vectors, "queries": query_vectors}
    with open(args.out, "w") as f:
        json.dump(out, f)
        f.write("\n")
    print(f"wrote {args.out}: {len(album_vectors)} albums, {len(query_vectors)} queries")


if __name__ == "__main__":
    main()
