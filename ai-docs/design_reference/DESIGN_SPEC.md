# Frontend Design Spec — match the official Shards of Infinity client

The five reference stills in this folder are the **canonical visual target** for
the game board UI. Goal (per user decision 2026-06-29): **match the layout and
chrome exactly, using our local card art** (`assets/cards/<id>.jpg`) for card
faces. Recreate the dark sci-fi board background; do NOT need the official
painted boss figure pixel-for-pixel, but approximate the dark blue-teal
server-room mood.

Reference images (landscape, ~2622×1206, aspect ≈ 2.17:1 — a phone in landscape):
- `01_board_playall.png` — main board, "Play All" state
- `02_board_focus.png` — same board, "Focus" toggle (gem:mastery 1:1) + played cards row
- `03_card_detail_recruit.png` — center-row card tapped → detail modal + circular **Recruit** button + L/R nav arrows
- `04_champion_exhaust.png` — champion (Volos) detail modal + circular **Exhaust** button
- `05_online_lobby.png` — metallic-framed "Online" lobby panel (Your Games / More Games / Create Game)

## Layout (board screen)

Three horizontal zones over a dark blue board background with a faint glowing
central figure:

1. **Top bar** (opponent): centered pill showing opponent avatar + name ("Hard
   AI") then three stat chips — health (red), mastery (gold octagon "1"), gems
   ("50"). Top-right: a teal beveled hamburger/menu button.
2. **Center row** (market): 6 cards in a row, evenly spaced, each with a thin
   glowing frame. A helper line above: "Drag to Play cards, Exhaust champions,
   or Recruit from the center row".
3. **Play area** (middle): mostly background; this is where the central glow
   sits and where dragged/played cards animate.
4. **Hand + resource zone** (bottom):
   - Left: **End Turn** button (beveled teal, italic gold text), below it a
     resource chip row (avatar, mastery, gems) and the **draw-pile count** in a
     green hex.
   - Center: the player's **hand** (5 cards) OR, in the Focus shot, the
     **played-this-turn** row.
   - A diamond badge showing a number (gems/power available, e.g. "5"/"6").
   - Right: the big **Play All** / **Focus** toggle button (square, beveled
     teal-green with gradient sheen). Focus mode shows a "1 : 1" gem:mastery
     ratio. Far right-bottom: **discard pile** count in a red-brown hex ("0").

## Card frame anatomy (match precisely)

- **Faction-colored border**: Homodeus=gold, Order=blue, Undergrowth=green,
  Wraethe=purple, neutral=grey/teal. Our `FactionColors` already encodes these.
- **Title bar** at top: card name, left-aligned, on a faction-tinted strip.
- **Cost**: top-right, in a circular/hex **gem teardrop** (blue) for recruit
  cost. Center-row cards show recruit cost here.
- **Art**: the painted card image fills the upper ~55% — use
  `assets/cards/<id>.jpg`.
- **Type banner**: lower-third, right-aligned italic — e.g. "Homodeus Champion",
  "Order Ally". A red **MERCENARY** tab overlaps the art's bottom-right when
  applicable.
- **Value badge**: bottom-right green chevron/hex showing the card's main
  output number (power/gems), e.g. Optio Crusher "4".
- **Text box**: rules text (regular weight) + a boxed mastery clause (e.g.
  "[10] Gain [5] instead.") + italic flavor text at the very bottom.
- **Champion shield**: champions show a shield value badge (blue shield icon,
  e.g. Command Seer "5", Zetta "5") on the lower-left of the art.

## Resource icon legend (use consistently everywhere)

| Resource | Icon | Color |
|---|---|---|
| Gems (currency) | teardrop / droplet | blue/cyan |
| Power (damage) | burst | red |
| Mastery | octagon/diamond | gold |
| Health | cross | green |
| Shield | shield | blue |

## Chrome / components

- **Beveled buttons**: metallic teal with a top-edge highlight and a soft inner
  gradient (lighter top → darker bottom), rounded corners, a thin lighter rim.
  Italic gold label for primary actions (End Turn). The Play All / Focus button
  is larger, more saturated teal-green, with a glossy diagonal sheen.
- **Circular action buttons** (in modals): large glowing blue discs with italic
  gold label ("Recruit", "Exhaust"), a bright rim light, sitting at the
  bottom-left of the focused card.
- **Card-detail modal**: the tapped card scales up centered with a bright
  cyan glow outline; left/right **nav arrows** (blue chevrons) flank it to move
  through the row; the context action disc sits bottom-left; tapping outside
  dismisses.
- **Menu/lobby panels** (`05`): heavy brushed-metal frame with angled corners, a
  title plate at top ("ONLINE"), an X close button top-right (teal), content
  area with section headers ("Your Games", "More Games"), game cards with a
  status label + player rows (colored ready dots), and a bottom **Create Game**
  bar button.

## Palette (extracted)

- Board background deep blue: ~`#0B1A2E` → `#10283F` gradient, with cyan accents.
- Chrome teal: highlight ~`#5FD0E6`, body ~`#1C7E96`, shadow ~`#0E4A5A`.
- Play All green-teal: ~`#19C39C` body with `#7DEBD0` sheen.
- Gold text/labels: ~`#E8C45A`.
- Faction borders: per `lib/ui/theme/faction_colors.dart` (already correct).

## What "matched" means (acceptance)

A live screenshot of our Flutter web build at the mockup's aspect ratio should,
side-by-side with `01_board_playall.png`:
- Place all zones (top bar, 6-card row, hand, End Turn, Play All, draw/discard
  counts) in the same relative positions.
- Use the same faction border colors and the same resource icon shapes/colors.
- Render beveled-teal buttons and faction-framed cards (not flat Material
  defaults).
- Show real card art from `assets/cards/`.

Pixel-perfection on the painted background is NOT required; structural +
chrome + color fidelity IS.

## Iteration loop

Use `scripts/capture_board.mjs` (Chrome DevTools Protocol) to launch the Flutter
web build and screenshot the board at 1310×600 (half the mockup, same aspect),
then compare to `01_board_playall.png`. Refine, re-capture, repeat. See
`scripts/README_capture.md`.
