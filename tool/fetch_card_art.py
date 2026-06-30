#!/usr/bin/env python3
"""Fetch and crop Fragments of Boundlessness card art from TTS spritesheet URLs.

Reads a card map (name, sheet URL, grid dims, row/col), downloads each unique
sheet once, crops each card by its grid cell, and saves to assets/cards/<id>.jpg.
Produces art_manifest.json mapping card id -> saved filename.

Usage:
  python tool/fetch_card_art.py <card_map.json> <assets/cards dir> <manifest_out.json>
"""
import json
import re
import sys
import urllib.request
from io import BytesIO

from PIL import Image

UA = {"User-Agent": "Mozilla/5.0 (card-art-fetch)"}


def slug(name: str) -> str:
    """Mirror the DB id-slugging: lowercase, strip punctuation, spaces->_,
    '(saved)'->_saved."""
    s = name.strip().lower()
    s = s.replace("(saved)", " saved ")
    s = re.sub(r"[''`.,:]", "", s)
    s = re.sub(r"[^a-z0-9]+", "_", s)
    s = re.sub(r"_+", "_", s).strip("_")
    return s


def fetch(url: str) -> Image.Image:
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=60) as r:
        data = r.read()
    return Image.open(BytesIO(data)).convert("RGB")


def main():
    map_path, out_dir, manifest_path = sys.argv[1], sys.argv[2], sys.argv[3]
    cards = json.load(open(map_path, encoding="utf-8"))

    sheet_cache: dict[str, Image.Image] = {}
    manifest = {}
    failures = []

    for c in cards:
        name = c["name"]
        cid = slug(name)
        url = c["sheet"]
        grid = c.get("grid", "1x1")
        cols, rows = (int(x) for x in grid.lower().split("x"))
        col, row = c.get("col", 0), c.get("row", 0)

        try:
            if url not in sheet_cache:
                sheet_cache[url] = fetch(url)
            sheet = sheet_cache[url]
            W, H = sheet.size
            cw, ch = W // cols, H // rows
            left, top = col * cw, row * ch
            crop = sheet.crop((left, top, left + cw, top + ch))
            out_file = f"{cid}.jpg"
            crop.save(f"{out_dir}/{out_file}", "JPEG", quality=90)
            manifest[cid] = {"name": name, "file": out_file,
                             "w": cw, "h": ch, "grid": grid}
            print(f"OK   {cid:32s} {cw}x{ch}  ({grid} @ r{row}c{col})")
        except Exception as e:  # noqa: BLE001
            failures.append({"name": name, "id": cid, "url": url, "error": str(e)})
            print(f"FAIL {cid:32s} {e}")

    json.dump(manifest, open(manifest_path, "w", encoding="utf-8"), indent=2)
    print(f"\nSaved {len(manifest)} crops; {len(failures)} failures.")
    if failures:
        json.dump(failures, open(manifest_path + ".failures.json", "w"), indent=2)
        for f in failures:
            print(f"  - {f['id']}: {f['error']}")


if __name__ == "__main__":
    main()
