# Card List Source — BGG full card list table

Source: user-pasted transcription from BoardGameGeek thread 3449758
("I created a full card list table", by Peter Horvath). This is the authoritative
metadata source for the card database scaffold. Effects/ability text are NOT in
this list — only name, amount, faction, set, chapter, card back, frame, and
co-op status.

## Author's ordering & labeling notes

- Starter deck cards (60) are intentionally NOT included (obvious).
- Ordered by: chapter (1–5) → card back (Normal/brown, then Black/co-op,
  then Purple/Destiny) → frame color (Black, then Grey; White not listed) →
  faction (player factions Aion→Wraethe; non-player faction-like groups
  alphabetical within their own category) → card name alphabetical.
- Non-player "faction-like" groups: co-op attack Bosses (Crimson Thorn…Vox),
  Shadow Champions (Aberrant…Talos), Ingeminex, Destiny.
- Set labels (per card symbols): Core, Relics [of the Future], Shadow [of
  Salvation], Into [the Horizon], Saga.
- Saga + Chapter 3 main-deck (brown back, black frame) = Kickstarter-only.
  5 more KS-only in Chapter 2 (which ones is uncertain).
- "Saved" cards in Chapter 3: "Saved" is a disambiguation label added by the
  author, NOT printed on the card (e.g. "Dash (Saved)").
- One card faction marked "Homodeus (typo!)" by the author — needs review.

## Known transcription typos to normalize (flagged by author or evident)

- "Le'shai Knight" vs "Le-shai Knight (Saved)" — same card, normalize apostrophe.
- "Cloude Master" → likely "Cloud Master" (Raidian).
- "Cloud Oracles" / "Cloude" inconsistency.
- "datic" lowercase in several names (e.g. "Keeper of datic Vessels",
  "Datic Inquisitors") — preserve as printed where known, flag uncertainty.
- "Mainfrane Abbot" → likely "Mainframe Abbot".
- "Crimson operative" capitalization (vs "Crimson Operative" in comments).
- "(Homodeus (typo!))" faction entry — verify correct faction.

## Cross-checks available in the thread

- KS-exclusive card list (applesin / SpidermanGeek / confirmed by Tim): the
  Chapter 3 brown-back/black-frame Saga cards, plus the Aion/Order/Undergrowth/
  Wraethe/Homodeus retail-added singles (Crimson Operative, Nexus Datic Hunter,
  Chlorophyte Guardian, Spirit Leech, Concussio and Mirus).
- Prism faction (retail-added): 2 relics, 3 center deck cards, 1 Ingeminex.

## Raw table (columns: Name | Amount | Faction | Set | Chapter | Back | Frame | Co-op only?)

> The full pasted table is preserved verbatim in the scaffold task input given to
> the consensus agent. Parse the columns positionally — the user pasted each
> column as a contiguous block (all Names, then all Amounts, then all Factions,
> etc.), so they must be zipped back together by row index.
