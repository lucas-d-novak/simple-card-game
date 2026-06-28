# lib/ui

Flutter UI layer for the Shards of Infinity card game.

## Structure

```
ui/
├── screens/
│   ├── game_setup_screen.dart      # Player count picker → starts game
│   ├── game_screen.dart            # Main game board (active)
│   └── home_screen.dart            # Legacy demo screen
├── widgets/
│   ├── game_card_widget.dart       # Styled card with faction colors, art, badges
│   ├── card_fan.dart               # Fan-of-cards hand display
│   ├── card_art.dart               # Procedural canvas art (faction patterns)
│   ├── resource_bar.dart           # Health/mastery/gems/power bar
│   └── playing_card_widget.dart    # Legacy card widget
└── theme/
    ├── game_theme.dart             # Dark board theme, colors
    └── faction_colors.dart         # Faction color palettes (primary/light/dark)
```

## Game screen layout (top to bottom)

1. **Turn indicator** — turn number and current player name
2. **Opponent area** — resource bar + champions (clickable to attack when you have power)
3. **Center row** — 6 market cards (tap affordable ones to buy)
4. **Play area** — your champions (persistent, gold border) + cards played this turn
5. **Action message** — feedback text (gold italic)
6. **Resource bar** — your health, mastery, gems, power, deck/discard counts
7. **Action buttons** — PLAY ALL | ATTACK | END TURN
8. **Card fan** — hand cards in a rotated fan (tap to select, tap again to play)

## Key interactions

- **Tap card in hand** → selects (raises it up, shows "TAP TO PLAY" label). **Tap again** → plays it.
- **Long-press any card** → shows card detail popup with full effect descriptions
- **PLAY ALL** → plays all hand cards left to right (does NOT auto-attack)
- **ATTACK** → spends all power attacking opponent (shows target picker in multiplayer)
- **Tap opponent champion** → attacks that champion (costs shield value in power)
- **Tap your champion** → activates it (once per turn, shows green checkmark when done)
- **END TURN** → ends turn (unspent power is lost per rules)
- **Tap center row card** → buys if affordable (highlighted with gold glow)
- **Banish/Scrap effects** → after playing a card with these effects, a selection dialog appears

## Card widget features

- Faction-colored header bar with card name and cost badge
- Asset image art with faction-tinted overlay (falls back to procedural art)
- Effect descriptions in info area
- Badges: shield value, GUARD, MERC, faction abbreviation
- Gold glow highlight when selected or affordable
- Long-press for full card detail popup
- AnimatedScale on just-played cards in play area

## Additional screens/overlays

- **Game over screen** — winner name, win condition (elimination vs mastery), final standings table (HP + mastery per player), Rematch and New Game buttons
- **ChooseOneEffect dialog** — buttons for each choice option (e.g., "2 gems" vs "2 power")
- **Banish dialog** — list of hand/discard cards to permanently remove
- **Scrap dialog** — list of center row cards to remove
- **Attack target dialog** — choose opponent in 3-4 player games
- **AI thinking overlay** — "AI is thinking..." indicator during AI turns

## Resource bar

- Health (red/green), Gems (cyan), Power (orange)
- **Mastery progress indicator** — bar filling toward 30, turns gold when maxed
- Deck/discard pile counts

## Theme

Dark board (navy/dark blue) with:
- Faction colors: Homodeus=Gold, Wraethe=Purple, Order=Blue, Undergrowth=Green
- Resource colors: Health=Red/Green, Gems=Cyan, Power=Orange, Mastery=Purple
- Gold accents for current player, selected cards, affordable items

## Legacy widgets

`home_screen.dart` and `playing_card_widget.dart` are kept for existing widget tests. They use `DeckService` and `ValueKey` strings. Don't modify their keys without updating `test/widget_test.dart`.
