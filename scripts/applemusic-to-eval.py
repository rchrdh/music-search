#!/usr/bin/env python3
"""Convert an Apple Music / iTunes library export into the eval tool's JSON.

Apple's Music app (macOS) exports a plist XML via:
    File > Library > Export Library…   ->   Library.xml

That file is track-level; the eval harness wants album-level entries:
    { "id", "title" (album), "artist", "genres" }

IDs are a short hash of artist+album, so they are stable across re-exports:
judgments files curated against one conversion stay valid after your library
grows and you re-export, as long as the album itself is still there.

Usage:
    python3 scripts/applemusic-to-eval.py ~/Music/Library.xml > my-library.json
    swift run musicsearch-eval "Albums that are like Brian Eno" --albums my-library.json
"""
import hashlib
import json
import plistlib
import sys


def stable_id(artist: str, album: str) -> str:
    key = f"{artist.lower()}\x1f{album.lower()}".encode()
    return hashlib.sha256(key).hexdigest()[:10]


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2

    with open(sys.argv[1], "rb") as f:
        library = plistlib.load(f)

    tracks = library.get("Tracks", {})
    albums: dict[tuple[str, str], dict] = {}

    for track in tracks.values():
        album = (track.get("Album") or "").strip()
        # Prefer the album artist so compilations/multi-disc sets collapse.
        # Compilation tracks without one would otherwise explode into one
        # album row per track artist — group them as Various Artists, which
        # is how MusicKit presents them in the app.
        artist = (track.get("Album Artist") or "").strip()
        if not artist:
            if track.get("Compilation"):
                artist = "Various Artists"
            else:
                artist = (track.get("Artist") or "").strip()
        if not album or not artist:
            continue  # singles / metadata-less items aren't useful here

        key = (artist.lower(), album.lower())
        entry = albums.setdefault(key, {"title": album, "artist": artist, "genres": []})
        genre = (track.get("Genre") or "").strip()
        if genre and genre not in entry["genres"]:
            entry["genres"].append(genre)

    out = []
    for entry in sorted(albums.values(), key=lambda e: (e["artist"], e["title"])):
        out.append({
            "id": stable_id(entry["artist"], entry["title"]),
            "title": entry["title"],
            "artist": entry["artist"],
            "genres": entry["genres"],
        })

    json.dump(out, sys.stdout, ensure_ascii=False, indent=2)
    print(f"\n# {len(out)} albums", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
