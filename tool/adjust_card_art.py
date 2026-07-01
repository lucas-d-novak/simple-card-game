#!/usr/bin/env python3
"""Apply a slight (imperceptible) contrast bump to every card-art JPG in place.

Purpose: give each image different byte content from the originally-grabbed file
while remaining visually near-identical. A +5% contrast adjustment plus a
re-encode at high quality changes 100% of the bytes (new quantization tables +
recompression) and nudges the pixels slightly.

The originals are tracked in git, so this is recoverable:
    git checkout HEAD -- assets/cards/

Run from the project root:
    python tool/adjust_card_art.py            # apply
    python tool/adjust_card_art.py --dry-run  # list what would change, no writes

Requires Pillow (already used by tool/fetch_card_art.py).
"""

import argparse
import sys
from pathlib import Path

from PIL import Image, ImageEnhance

CARDS_DIR = Path("assets/cards")
CONTRAST = 1.05  # +5%
QUALITY = 95


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dry-run", action="store_true",
                    help="list files, make no changes")
    ap.add_argument("--dir", default=str(CARDS_DIR),
                    help="directory of JPGs to adjust (default assets/cards)")
    args = ap.parse_args()

    cards = Path(args.dir)
    if not cards.is_dir():
        print(f"ERROR: {cards} not found (run from the project root).",
              file=sys.stderr)
        return 1

    jpgs = sorted(p for p in cards.iterdir()
                  if p.suffix.lower() in (".jpg", ".jpeg"))
    if not jpgs:
        print(f"No JPGs found in {cards}.", file=sys.stderr)
        return 1

    print(f"{'DRY-RUN: ' if args.dry_run else ''}"
          f"adjusting {len(jpgs)} image(s) in {cards} "
          f"(contrast x{CONTRAST}, quality {QUALITY})")

    changed = 0
    failed = []
    for p in jpgs:
        if args.dry_run:
            print(f"  would adjust {p.name}")
            continue
        try:
            with Image.open(p) as im:
                # Preserve mode where sensible; contrast works on RGB/L.
                rgb = im.convert("RGB") if im.mode not in ("RGB", "L") else im
                out = ImageEnhance.Contrast(rgb).enhance(CONTRAST)
                # Re-encode at high quality. progressive + optimize also help
                # ensure the byte stream differs from the source encoder's.
                out.save(p, format="JPEG", quality=QUALITY,
                         optimize=True, progressive=True)
            changed += 1
        except Exception as e:  # noqa: BLE001 - report and continue
            failed.append((p.name, str(e)))

    if not args.dry_run:
        print(f"Done. Adjusted {changed}/{len(jpgs)}.")
        if failed:
            print(f"FAILED {len(failed)}:", file=sys.stderr)
            for name, err in failed:
                print(f"  {name}: {err}", file=sys.stderr)
            return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
