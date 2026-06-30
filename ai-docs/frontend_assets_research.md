# Frontend Assets & Design Research: Fragments of Boundlessness Digital Card Game

> Compiled for the simple-card-game Flutter project.
> Last updated: 2026-06-27
>
> **Cross-references**: Game rules, faction identities, and card data are the source of truth in `fragments_of_boundlessness_mechanics.md`. Visual iteration workflow is in `visual_iteration_system.md`. Colors and themes in this doc must match the faction definitions in the mechanics doc (Section 9).

---

## Table of Contents

1. [Flutter Card Game Packages/Libraries](#1-flutter-card-game-packageslibraries)
2. [Card UI Design Patterns](#2-card-ui-design-patterns)
3. [Free/Open Art Assets](#3-freeopen-art-assets)
4. [Icon Libraries](#4-icon-libraries)
5. [Card Frame/Template Design](#5-card-frametemplate-design)
6. [Animation and Polish](#6-animation-and-polish)
7. [Color Palettes](#7-color-palettes)
8. [Typography](#8-typography)
9. [Sound Effects](#9-sound-effects)
10. [Responsive Layout](#10-responsive-layout)
11. [Research Confidence](#11-research-confidence)

---

## 1. Flutter Card Game Packages/Libraries

### Dedicated Card/Game Packages

| Package | Description | Status / Notes |
|---------|-------------|----------------|
| **`playing_cards`** (pub.dev) | Renders standard playing card visuals. Not directly for custom card games but useful reference for card rendering approach. | Niche; limited maintenance. |
| **`flame`** (pub.dev) | Full 2D game engine for Flutter. Sprite rendering, game loop, collision detection, particle effects. Excellent for building a card game from scratch with animations. | Very actively maintained (>7k GitHub stars). Version 1.x+ stable. |
| **`flame_forge2d`** | Physics extension for Flame. Could be used for card physics (tossing, bouncing). | Active, part of Flame ecosystem. |
| **`bonfire`** (pub.dev) | RPG game engine built on Flame. Overkill for a card game but demonstrates Flame's extensibility. | Active. |
| **`flutter_draggable_gridview`** | Drag-and-drop grid. Could work for card hand/market row arrangement. | Moderate maintenance. |
| **`reorderables`** | Reorderable lists and grids via drag-and-drop. Useful for hand reordering. | Moderate maintenance. |
| **`flutter_animate`** (pub.dev) | Declarative animation library. Excellent for card entry/exit animations, shimmer effects, staggered animations. | Actively maintained, high quality. ~3k+ likes. |
| **`rive`** (pub.dev) | Runtime for Rive animations. Useful for complex card effects, particle bursts, character animations. | Actively maintained. Professional quality. |
| **`lottie`** (pub.dev) | After Effects animations via Lottie JSON. Good for effects like card glow, mastery level-up, damage bursts. | Actively maintained. |

### Recommendation

For a deck-builder like Fragments of Boundlessness, the best approach is:
- **Use Flame** if you want a full game-engine approach with sprite-based rendering, custom draw calls, and a game loop. Best for complex board states, particle effects, and smooth 60fps animations.
- **Use pure Flutter widgets + `flutter_animate`** if you want to stay in the widget tree for easier layout, accessibility, and responsive design. Card games are mostly static layout with occasional animation bursts, so this works well.
- **Hybrid approach**: Use Flutter widgets for layout/UI chrome, and an embedded Flame widget for the play area where cards animate.

### Drag-and-Drop for Card Play

Flutter's built-in `Draggable` and `DragTarget` widgets are sufficient for card interactions (drag from hand to play area). For more polish:
- `flutter_draggable_gridview` for market row
- Custom `GestureDetector` + `AnimatedPositioned` for smooth card movement
- `InteractiveViewer` for zoom/pan on complex board states

---

## 2. Card UI Design Patterns

### Reference Games Analysis

#### Slay the Spire (PC/Mobile)
- **Layout**: Hand of cards fanned at bottom; energy/mana top-left; draw pile bottom-left; discard bottom-right; enemies top half.
- **Card design**: Portrait orientation, art takes top 60%, text bottom 40%. Cost in top-left circle. Card type banner across middle.
- **What works**: Clear card costs visible even when fanned. Color-coded card types (red=attack, green=skill, blue=power). Hover/tap to enlarge.
- **Takeaway for us**: Fan layout for hand, tap-to-zoom for detail, color-code by faction.

#### Star Realms (Mobile App - closest to Fragments of Boundlessness)
- **Layout**: Trade row (market) across center. Player areas top and bottom. Hand at very bottom fanned.
- **Card design**: Landscape-ish small cards in trade row; portrait in hand. Faction colors on card borders (blue=Trade Federation, red=Machine Cult, green=Blob, yellow=Star Empire).
- **What works**: Compact trade row showing 5 cards. Clear faction identification through border colors. Combat/trade values in distinct icon badges.
- **Takeaway for us**: This is the closest reference. Copy the trade row + hand + player board layout. Use faction border colors heavily. Note: Fragments of Boundlessness uses a **6-card** center row, not 5 (see `fragments_of_boundlessness_mechanics.md` Section 10).

#### Hearthstone (Mobile/PC)
- **Layout**: Battlefield in center, hand fanned at bottom. Mana crystals bottom-right. Hero portrait bottom-center.
- **Card design**: Portrait, ornate frame. Mana cost top-left blue gem. Attack bottom-left, health bottom-right. Name banner across center.
- **What works**: Extremely polished card entrance animations. Cards glow when playable. Drag-to-play feel is iconic.
- **Takeaway for us**: Aspire to the drag-to-play interaction. Glow effect for affordable cards.

#### Dominion Online (Browser)
- **Layout**: Supply piles in grid on left. Play area center. Hand bottom.
- **Card design**: Simple, information-dense. Art is small. Cost in bottom-left.
- **What works**: Information density. Can see many cards at once. Log on right side.
- **Takeaway for us**: Action log is valuable for deck-builders. Keep information density high.

### Deck-Builder Specific UI Patterns

1. **Trade/Market Row**: 5-6 cards displayed face-up. Tap to buy. Show cost prominently. Auto-refill from trade deck.
2. **Hand Display**: Fan of 5 cards at screen bottom. Tap to play, or drag upward to play area.
3. **Play Area / "In Play" Zone**: Cards played this turn shown in a row. Clear visual boundary from hand.
4. **Deck/Discard Piles**: Stack icons with count badges. Tap to view discard contents.
5. **Player Stats Bar**: Health/shields, attack accumulated, gems/currency accumulated, mastery track.
6. **Opponent Area**: Mirrored at top of screen (in multiplayer). Minimized cards.
7. **End Turn Button**: Prominent, centered or right side.

---

## 3. Free/Open Art Assets

### Sci-Fi / Fantasy Card Art Sources

| Source | URL | License | Notes |
|--------|-----|---------|-------|
| **OpenGameArt.org** | https://opengameart.org/ | Varies (CC0, CC-BY, CC-BY-SA, GPL) | Large collection of 2D game art. Search "sci-fi", "fantasy", "card". Many character portraits and icons. Filter by license. |
| **Kenney.nl** | https://kenney.nl/assets | CC0 (Public Domain) | Excellent quality asset packs. "Sci-Fi RTS" pack, "UI Pack (Sci-Fi)", "Game Icons" pack. All completely free, no attribution required. |
| **game-icons.net** | https://game-icons.net/ | CC-BY 3.0 | 4000+ game-related icons. Swords, shields, crystals, skulls, energy bolts, etc. SVG format. Ideal for card effect icons. |
| **Itch.io Asset Packs** | https://itch.io/game-assets/free/tag-card-game | Varies (check each) | Many free card game assets, card backs, card frames. Search "card game", "sci-fi", "fantasy cards". |
| **Unsplash** | https://unsplash.com/ | Unsplash License (free commercial use) | High-quality photos that could serve as card art backgrounds. Search "nebula", "crystal", "dark fantasy". |
| **Pixabay** | https://pixabay.com/ | Pixabay License (free commercial use) | Similar to Unsplash, illustrations and photos. |
| **SVGRepo** | https://www.svgrepo.com/ | Varies (many CC0/MIT) | Free SVG icons and illustrations. Good for UI elements. |
| **Craftpix.net** | https://craftpix.net/freebies/ | Free for personal/commercial | Free game assets including sci-fi UI elements, card frames, fantasy icons. |
| **Open Clipart** | https://openclipart.org/ | CC0 | Public domain vector art. Basic quality but useful for prototyping. |

### AI-Generated Art Consideration

For a Fragments of Boundlessness adaptation, card art could be generated using AI image tools (Midjourney, DALL-E, Stable Diffusion) for prototyping. For a production game:
- Use AI art for placeholders/prototypes
- Commission or use properly licensed art for release
- Stable Diffusion (open source) models can run locally for unlimited generations

### Recommended Starting Kit

For immediate prototyping:
1. **Kenney.nl Sci-Fi UI Pack** for card frames and UI chrome
2. **game-icons.net** for all card effect/ability icons
3. **OpenGameArt.org** character portraits for card art
4. Placeholder colored rectangles with text for cards during development

---

## 4. Icon Libraries

### Flutter-Compatible Icon Packs

| Icon Need | Recommended Source | Flutter Integration |
|-----------|-------------------|---------------------|
| **Attack/Power** (sword, fist, explosion) | game-icons.net, Material Icons (`Icons.flash_on`, `Icons.sports_mma`) | SVG via `flutter_svg` package, or use Material Icons built-in |
| **Gems/Currency** (diamond, coin, crystal) | game-icons.net (`crystal-growth`, `gem-chain`), Material Icons (`Icons.diamond`, `Icons.monetization_on`) | Same |
| **Shields/Defense** (shield, barrier) | game-icons.net (`shield`, `energy-shield`), Material Icons (`Icons.shield`) | Same |
| **Mastery/Leveling** (level up arrow, star) | game-icons.net (`upgrade`, `rank-3`), Material Icons (`Icons.trending_up`, `Icons.star`) | Same |
| **Card Draw** (deck, hand of cards) | game-icons.net (`card-draw`, `card-pickup`), custom SVGs | `flutter_svg` |
| **Faction Symbols** | Custom designed; game-icons.net as starting points | Custom SVGs or `CustomPainter` |
| **Health/HP** (heart, life) | Material Icons (`Icons.favorite`), game-icons.net (`hearts`) | Built-in |

### Key Flutter Packages for Icons

| Package | Description |
|---------|-------------|
| **`flutter_svg`** (pub.dev) | Renders SVG files. Essential for custom game icons from game-icons.net or custom designs. Actively maintained. |
| **`font_awesome_flutter`** (pub.dev) | FontAwesome icons in Flutter. Has shield, bolt, gem, skull icons. |
| **`material_design_icons_flutter`** (pub.dev) | Extended Material Design icons. Includes sword, shield, cards, many game-relevant icons. |
| **`cupertino_icons`** | Built into Flutter. Limited game relevance. |
| **`phosphor_flutter`** (pub.dev) | Phosphor icon set. Clean, modern. Has sword, shield, lightning, crown, diamond, etc. |
| **`fluentui_system_icons`** (pub.dev) | Microsoft's Fluent icons. Large set, some game-relevant options. |

### Custom Icon Strategy for Fragments of Boundlessness

For faction symbols specifically, recommend:
1. Download base shapes from game-icons.net (CC-BY 3.0, attribute "Lorc, Delapouite" etc.)
2. Customize colors and styling in a vector editor (Figma, Inkscape)
3. Export as SVG, load with `flutter_svg`
4. Or use `CustomPainter` to draw programmatically for dynamic color changes

### Specific game-icons.net Icons (by concept)

- **Attack**: `sword-clash`, `crossed-swords`, `lightning-bolt`, `laser-blast`
- **Currency/Gems**: `gem-chain`, `crystal-growth`, `cut-diamond`, `gold-bar`
- **Defense/Shield**: `shield`, `energy-shield`, `bordered-shield`, `armor-upgrade`
- **Mastery**: `upgrade`, `level-four-advanced`, `ankh`, `enlightenment`
- **Card operations**: `card-draw`, `card-pickup`, `card-discard`, `stack`
- **Factions** (potential starting points): `robot-golem` (tech), `fairy` (nature), `crowned-skull` (death/void), `solar-system` (cosmic)

---

## 5. Card Frame/Template Design

### Card Anatomy for Fragments of Boundlessness

A typical deck-builder card needs these zones:

```
+---------------------------+
|  [Cost]        [Faction]  |   <- Top bar: cost (gems) + faction icon/color
|---------------------------|
|                           |
|        [CARD ART]         |   <- Art area: ~50-60% of card height
|                           |
|---------------------------|
|  [Card Name]              |   <- Name banner
|---------------------------|
|  [Type: Champion/Action]  |   <- Card type
|  [Effect text area]       |   <- Rules text, keywords
|  [Ally ability text]      |   <- Faction synergy bonus
|---------------------------|
|  [Attack]      [Defense]  |   <- Bottom stats (if applicable)
+---------------------------+
```

### Implementation Approaches in Flutter

#### Approach 1: Widget Composition (Recommended for starting)
```
Card widget = Stack(
  Container(           // card border with faction color
    Column(
      Row(cost, faction_icon),   // top bar
      Expanded(Image),           // art area
      Text(name),                // name
      Text(type),                // type line
      Expanded(Text(effect)),    // rules text
      Row(attack, defense),      // stats
    )
  )
)
```
- Pros: Easy to build, responsive, text wraps naturally, accessible
- Cons: Less visually distinctive than custom-painted

#### Approach 2: CustomPainter
- Draw card frame with `Canvas` API
- Full control over bezier curves, gradients, glow effects
- Can create ornate faction-specific borders
- Cons: More complex, text layout must be manual

#### Approach 3: Pre-rendered Frame Images
- Design card frames in Figma/Photoshop (one per faction)
- Export as PNG with transparent art area
- Overlay art and text programmatically
- Pros: Highest visual quality, designer-friendly
- Cons: Larger asset size, less dynamic

### Card Frame Design Tools

| Tool | Use Case | URL |
|------|----------|-----|
| **Figma** | Design card templates with components/variants per faction. Free tier. | https://figma.com/ |
| **Canva** | Quick card mockups with templates | https://canva.com/ |
| **CardMaker (Board Game)** | Dedicated card template tool | https://cardmaker.jharkness.com/ |
| **Magic Set Editor** | Card template editor (MTG-style), good for reference | https://magicseteditor.boards.net/ |
| **Inkscape** | Free vector editor for card frames | https://inkscape.org/ |
| **Nandeck** | Programmatic card generation | http://www.nandeck.com/ |

### Card Sizing

- **Standard card ratio**: 2.5 x 3.5 inches = 5:7 ratio (~0.714 aspect ratio)
- **In Flutter**: Use `AspectRatio(aspectRatio: 5/7)` or `ConstrainedBox`
- **Mobile hand**: Cards ~80-120px wide in fan, expand to ~250px on tap
- **Tablet**: Cards ~120-160px wide in fan
- **Desktop**: Cards ~150-200px wide in fan

### Faction Border Design Suggestions

Each faction should have a distinct border treatment (see `fragments_of_boundlessness_mechanics.md` Section 9 for faction themes):
- **Homodeus (Blue)**: Clean geometric lines, circuit-board pattern, blue glow — tech/transcendence
- **Wraethe (Purple)**: Sharp angular corners, dark purple/black with glow edges — destruction/chaos
- **Order of the New Dawn (Gold)**: Ornate borders, radiant golden trim, shield motifs — healing/defense
- **Undergrowth (Green)**: Vine/tendril decorations, organic curves, earthy gradient — nature/growth

---

## 6. Animation and Polish

### Card Animation Catalog

| Animation | When Used | Flutter Approach |
|-----------|-----------|------------------|
| **Card Draw** | Drawing from deck to hand | `AnimatedPositioned` moving from deck position to hand. Add slight rotation. 300-500ms duration. |
| **Card Play** | Playing card from hand to play area | `AnimatedPositioned` + `AnimatedScale` (slight grow then shrink). 200-400ms. |
| **Card Buy** | Buying from market | Card slides to discard pile with a coin/gem particle burst. |
| **Card Flip** | Revealing a card | `Transform(alignment: center, transform: Matrix4.rotationY(angle))` animated. 400ms. |
| **Card Fan** | Hand arrangement | `Transform(alignment: bottomCenter, transform: Matrix4.rotationZ(angle))` with staggered positions. |
| **Damage Effect** | Attack hits opponent | Screen shake (`Transform.translate` with rapid oscillation). Red flash overlay. |
| **Mastery Level-Up** | Mastery increases | Pulsing glow, particle burst, number counter animation. |
| **Shuffle** | Deck shuffle | Multiple cards flutter animation, or a simple shake animation on deck pile. |
| **Card Hover/Select** | Tap or hover on card | `AnimatedScale` to 1.1x + elevation increase + glow border. 150ms. |
| **Card Discard** | Card goes to discard | Slide + fade + slight rotation toward discard pile. 300ms. |
| **Turn Transition** | Between player turns | Overlay slide or fade with "Your Turn" / "Opponent's Turn". |

### Flutter Animation Packages & Tools

| Package/Tool | Use For | Notes |
|-------------|---------|-------|
| **`flutter_animate`** (pub.dev) | Declarative animation chains. Fade, slide, scale, blur, shimmer, shake. | Excellent API. Chain effects: `widget.animate().fadeIn().slideY()`. Highly recommended. |
| **`rive`** (pub.dev) | Complex vector animations (card effects, character reactions, mastery gauge). | Create in Rive editor (free tier), export as .riv file. |
| **`lottie`** (pub.dev) | After Effects animations for effects like explosions, sparkles, energy bursts. | Many free Lottie animations on lottiefiles.com. |
| **`animated_text_kit`** (pub.dev) | Animated text for damage numbers, "+3 Attack", "Level Up!" | Typewriter, fade, scale effects. |
| **`confetti`** (pub.dev) | Particle confetti bursts for victories, level-ups. | Simple to use, customizable. |
| **`spritewidget`** (pub.dev) | Sprite-based particles and effects. | Older but works for particle effects. |
| **Implicit Animations (built-in)** | `AnimatedContainer`, `AnimatedOpacity`, `AnimatedPositioned`, `AnimatedAlign`, `AnimatedDefaultTextStyle` | Zero dependencies. Great for most card game needs. |
| **`Hero` widget (built-in)** | Shared element transitions when navigating to card detail view. | Built into Flutter. |

### Animation Best Practices for Card Games

1. **Use curves**: `Curves.easeOutBack` for card arrival (slight overshoot), `Curves.easeIn` for departure
2. **Stagger hand animations**: When drawing multiple cards, stagger by 100ms each
3. **Haptic feedback**: `HapticFeedback.lightImpact()` on card play (mobile only)
4. **Particle effects**: Use Flame's `ParticleComponent` or Lottie for gem/shard bursts
5. **Performance**: Keep animations under 16ms per frame. Use `RepaintBoundary` around animated areas
6. **Reduce motion**: Respect `MediaQuery.of(context).disableAnimations` for accessibility

### Free Lottie Animation Resources

- **LottieFiles.com**: Search "card flip", "explosion", "sparkle", "level up", "coin". Many free animations available.
- **IconScout Lottie**: Additional free Lottie animations
- URL: https://lottiefiles.com/

---

## 7. Color Palettes

### Faction Color Palettes

Fragments of Boundlessness has four factions. Here are suggested color palettes inspired by the original game's aesthetic, with hex codes ready for Flutter (`Color(0xFF______)`).

> **Cross-ref**: Faction identities, themes, and mechanics are defined in `fragments_of_boundlessness_mechanics.md` Section 9. Colors below must match those definitions.

#### Faction 1: Homodeus (Technology/Knowledge/Transcendence) - BLUE
| Role | Hex | Swatch |
|------|-----|--------|
| Primary | `#1565C0` | Royal blue |
| Dark | `#0D47A1` | Navy blue |
| Light | `#90CAF9` | Sky blue |
| Accent | `#448AFF` | Bright blue |
| Card border gradient | `#0D47A1` to `#1565C0` | Dark to bright |

#### Faction 2: Wraethe (Destruction/Aggression/Chaos) - RED/PURPLE
| Role | Hex | Swatch |
|------|-----|--------|
| Primary | `#9C27B0` | Deep purple |
| Dark | `#4A0072` | Near-black purple |
| Light | `#CE93D8` | Lavender |
| Accent | `#EA80FC` | Neon purple |
| Card border gradient | `#4A0072` to `#9C27B0` | Dark to bright |

#### Faction 3: Order of the New Dawn (Healing/Defense/Unity) - GOLD/YELLOW
| Role | Hex | Swatch |
|------|-----|--------|
| Primary | `#F9A825` | Rich gold |
| Dark | `#F57F17` | Deep amber |
| Light | `#FFF176` | Pale yellow |
| Accent | `#FFD740` | Bright gold |
| Card border gradient | `#F57F17` to `#F9A825` | Dark to bright |

#### Faction 4: Undergrowth (Nature/Growth/Overwhelming Force) - GREEN
| Role | Hex | Swatch |
|------|-----|--------|
| Primary | `#4CAF50` | Forest green |
| Dark | `#1B5E20` | Dark forest |
| Light | `#A5D6A7` | Pale green |
| Accent | `#76FF03` | Lime burst |
| Card border gradient | `#1B5E20` to `#4CAF50` | Dark to bright |

#### Neutral / Unaligned Cards
| Role | Hex | Swatch |
|------|-----|--------|
| Primary | `#757575` | Medium grey |
| Dark | `#424242` | Dark grey |
| Light | `#E0E0E0` | Light grey |
| Accent | `#FFD740` | Gold (for gem/currency) |
| Card border gradient | `#424242` to `#757575` | Dark to bright |

### UI Chrome Colors (Non-Card)

| Element | Hex | Notes |
|---------|-----|-------|
| Background (dark theme) | `#121212` | Material dark surface |
| Surface | `#1E1E1E` | Cards, panels |
| Surface variant | `#2C2C2C` | Elevated surfaces |
| Primary text | `#FFFFFF` | White on dark |
| Secondary text | `#B0B0B0` | Muted info |
| Health/HP | `#EF5350` | Red |
| Attack | `#FF7043` | Orange-red |
| Currency/Gems | `#FFD740` | Gold |
| Mastery | `#AB47BC` | Purple-pink |
| Success/Heal | `#66BB6A` | Green |
| Warning | `#FFA726` | Amber |

### Flutter Implementation

```dart
class FactionColors {
  static const homodeus = Color(0xFF1565C0);    // Blue — tech/knowledge
  static const wraethe = Color(0xFF9C27B0);     // Purple — destruction/aggression
  static const order = Color(0xFFF9A825);       // Gold — healing/defense
  static const undergrowth = Color(0xFF4CAF50); // Green — nature/growth
  static const neutral = Color(0xFF757575);     // Grey — factionless
}
```

Use `ThemeExtension<T>` in Flutter 3.x+ to inject faction colors into the theme system.

---

## 8. Typography

### Recommended Fonts (Google Fonts - free, Flutter-compatible)

All of these are available via the `google_fonts` Flutter package (pub.dev) or can be bundled as assets.

#### Card Title / Name Font
| Font | Style | Why |
|------|-------|-----|
| **Orbitron** | Geometric, sci-fi | Perfect for tech/sci-fi card game. Angular, futuristic. |
| **Rajdhani** | Semi-condensed, technical | Readable at small sizes, sci-fi feel. Good for card names. |
| **Exo 2** | Geometric sans-serif | Modern, slightly futuristic. Good readability. |
| **Audiowide** | Futuristic display | Strong sci-fi identity. Best for titles/headers only (less readable at small sizes). |
| **Chakra Petch** | Thai-inspired geometric | Unique, sci-fi aesthetic. Good for card names. |

#### Card Body / Effect Text Font
| Font | Style | Why |
|------|-------|-----|
| **Roboto** | Neutral sans-serif | Flutter default. Excellent readability at all sizes. |
| **Source Sans 3** | Humanist sans-serif | Slightly warmer than Roboto. Great for body text. |
| **Inter** | Modern sans-serif | Designed for screens. Excellent at small sizes. |
| **Nunito Sans** | Rounded sans-serif | Friendly, readable. Good contrast with angular title fonts. |

#### Numbers / Stats Font
| Font | Style | Why |
|------|-------|-----|
| **Oswald** | Condensed sans-serif | Numbers look great, compact. Good for stat badges. |
| **Bebas Neue** | All-caps condensed | Bold numbers. Good for damage callouts. |
| **Roboto Mono** | Monospace | Consistent number widths. Prevents layout shift when numbers change. |

#### Flavor Text / Lore Font
| Font | Style | Why |
|------|-------|-----|
| **Lora** | Serif | Elegant, readable. Good for flavor text/lore quotes. |
| **EB Garamond** | Classic serif | Traditional card game feel for lore text. |

### Flutter Implementation

```dart
// In pubspec.yaml, add:
// dependencies:
//   google_fonts: ^6.0.0

import 'package:google_fonts/google_fonts.dart';

// Card title
TextStyle cardTitle = GoogleFonts.orbitron(
  fontSize: 14,
  fontWeight: FontWeight.w700,
  color: Colors.white,
);

// Card body text
TextStyle cardBody = GoogleFonts.inter(
  fontSize: 11,
  fontWeight: FontWeight.w400,
  color: Colors.white,
);

// Stat numbers
TextStyle statNumber = GoogleFonts.oswald(
  fontSize: 18,
  fontWeight: FontWeight.w700,
  color: Colors.white,
);
```

### Typography Hierarchy for Card Game UI

1. **Game title / Logo**: Audiowide or Orbitron, 24-32px, bold
2. **Card names**: Orbitron or Rajdhani, 12-16px, semibold
3. **Card effect text**: Inter or Roboto, 10-12px, regular
4. **Stat numbers (cost, attack, defense)**: Oswald or Bebas Neue, 16-20px, bold
5. **UI labels (buttons, menu)**: Inter or Roboto, 14px, medium
6. **Flavor text**: Lora italic, 9-10px
7. **Game log**: Roboto Mono, 11px, regular

---

## 9. Sound Effects

### Free Sound Effect Libraries

| Source | URL | License | Notes |
|--------|-----|---------|-------|
| **Freesound.org** | https://freesound.org/ | Varies (CC0, CC-BY, CC-BY-NC) | Massive library. Filter by license. Search "card", "whoosh", "coin", "magic". |
| **OpenGameArt.org** | https://opengameart.org/ (audio section) | Varies (CC0, CC-BY) | Game-specific sounds. Search "card game", "UI sounds", "fantasy". |
| **Kenney.nl** | https://kenney.nl/assets?q=audio | CC0 (Public Domain) | "UI Audio" pack, "Impact Sounds" pack. High quality, no attribution needed. |
| **Mixkit** | https://mixkit.co/free-sound-effects/ | Mixkit License (free) | Good quality. Search "card", "game", "magic". |
| **Pixabay Audio** | https://pixabay.com/sound-effects/ | Pixabay License (free) | Growing library of SFX. |
| **ZapSplat** | https://www.zapsplat.com/ | Free with attribution (or paid for no attribution) | Large library, game sounds category. |
| **Sonniss GDC Audio Bundles** | https://sonniss.com/gameaudiogdc | Royalty-free | Annual free GDC bundles with thousands of professional sound effects. Check for past years' bundles. |

### Specific Sounds Needed

| Game Action | Sound Description | Search Terms |
|-------------|-------------------|--------------|
| Card draw | Paper slide/whoosh | "card draw", "paper slide", "card flip" |
| Card play | Card slap on table | "card place", "card slam", "paper thud" |
| Card buy/acquire | Coin clink + card sound | "coin purchase", "buy item", "gem collect" |
| Attack/damage | Impact, energy blast | "punch impact", "energy blast", "sci-fi hit" |
| Shield/defense | Metallic block | "shield block", "metal clang", "force field" |
| Mastery level-up | Rising chime, power-up | "level up", "power up", "achievement" |
| Shuffle deck | Card shuffle | "card shuffle", "deck shuffle" |
| Turn start | Notification chime | "turn notification", "bell chime" |
| Victory | Fanfare | "victory fanfare", "win jingle" |
| Defeat | Somber tone | "defeat", "game over", "lose" |
| Button click | UI click | "button click", "menu select" |
| Hover/select | Subtle tick | "hover", "tick", "select" |

### Flutter Audio Packages

| Package | Description | Notes |
|---------|-------------|-------|
| **`audioplayers`** (pub.dev) | Play audio from assets, network, or file. Cross-platform. | Most popular. Actively maintained. Good for SFX. |
| **`just_audio`** (pub.dev) | Feature-rich audio player. Gapless playback, speed control. | Excellent quality. Good for background music. |
| **`flame_audio`** (pub.dev) | Audio for Flame games. Built on `audioplayers`. | Use if using Flame engine. |
| **`soundpool`** (pub.dev) | Low-latency sound effects. Preloads sounds for instant playback. | Best for rapid-fire SFX (card plays, attacks). |

### Recommended Audio Strategy

1. Use `audioplayers` or `soundpool` for short SFX (card draw, play, attack)
2. Use `just_audio` for background music/ambience
3. Preload all SFX at app startup into a sound pool
4. Keep SFX files short (<2 seconds) and small (<100KB each)
5. Use OGG format for best cross-platform compatibility (MP3 fallback for iOS)
6. Implement a volume control and mute toggle

---

## 10. Responsive Layout

### Breakpoint Strategy for Card Games

| Platform | Width Range | Layout Approach |
|----------|-------------|-----------------|
| **Phone portrait** | 320-480px | Compact: hand scrolls horizontally, market stacked vertically, stats collapsed |
| **Phone landscape** | 568-896px | Moderate: hand fanned at bottom, market row visible, stats sidebar |
| **Tablet portrait** | 768-1024px | Comfortable: full hand visible fanned, market row, both player areas |
| **Tablet landscape** | 1024-1366px | Ideal: full game board visible, no scrolling needed |
| **Desktop browser** | 1200-1920px+ | Spacious: card details on hover, game log sidebar, larger cards |

### Flutter Responsive Techniques

#### 1. LayoutBuilder + Breakpoints
```dart
LayoutBuilder(builder: (context, constraints) {
  if (constraints.maxWidth < 600) return MobileGameLayout();
  if (constraints.maxWidth < 1024) return TabletGameLayout();
  return DesktopGameLayout();
})
```

#### 2. Card Sizing Strategy
```dart
// Calculate card width based on available space and hand size
double cardWidth = (availableWidth / handSize).clamp(60.0, 180.0);
double cardHeight = cardWidth * 7 / 5; // maintain 5:7 ratio
```

#### 3. Hand Fan Layout
- **Mobile**: Cards overlap heavily (show 30% of each card). Horizontal scroll if >6 cards. Tap to expand/select.
- **Tablet**: Cards overlap moderately (show 50% of each card). All visible for 5-7 card hand.
- **Desktop**: Cards overlap slightly (show 70% of each card). Hover to raise. Click to play.

#### 4. Adaptive UI Elements

| Element | Mobile | Tablet | Desktop |
|---------|--------|--------|---------|
| Market row | Scrollable, 3 visible | All 5-6 visible | All visible + card details |
| Hand | Scrollable fan, tap to select | Fan, all visible | Fan with hover effects |
| Player stats | Icon-only top bar | Icons + values | Full stat bar with labels |
| Game log | Hidden, tap to open | Collapsible sidebar | Always-visible sidebar |
| Card detail | Full-screen overlay | Modal popup | Hover tooltip / side panel |
| Opponent area | Minimal (HP only) | Compact cards | Mirrored play area |
| End turn button | FAB (floating action button) | Large bottom-right | Button in action bar |

### Flutter Packages for Responsive Design

| Package | Use Case |
|---------|----------|
| **`responsive_builder`** (pub.dev) | Screen type detection, responsive widgets |
| **`responsive_framework`** (pub.dev) | Auto-scale UI, breakpoint management |
| **`flutter_screenutil`** (pub.dev) | Scale UI based on design dimensions |
| Built-in `MediaQuery` | Access screen size, orientation, text scale |
| Built-in `LayoutBuilder` | Parent-constraint-based layouts |
| Built-in `OrientationBuilder` | React to orientation changes |

### Game Board Layout Architecture

```
Desktop Layout:
+-------+---------------------------+--------+
| Opp.  |      Market/Trade Row     | Game   |
| Stats |  [card][card][card][card]  | Log    |
|       |                           |        |
+-------+---------------------------+        |
|          Play Area (in-play)      |        |
|    [played][played][played]       |        |
+-----------------------------------+        |
|        Hand (fanned cards)        |        |
|   [c1][c2][c3][c4][c5]           |        |
+-------+---------------------------+--------+
| Deck  |      Player Stats         | End    |
| Disc. |  HP | ATK | Gems | Mast. | Turn   |
+-------+---------------------------+--------+

Mobile Layout (Portrait):
+---------------------------+
| Opponent: HP 50  ATK 0    |
+---------------------------+
| Market (scroll)           |
| [card][card][card]>>>     |
+---------------------------+
| Play Area                 |
| [played][played]          |
+---------------------------+
| HP:50 ATK:0 Gem:3 Mst:5  |
+---------------------------+
| Hand (scroll)             |
| [c1][c2][c3][c4]>>>      |
+--[Deck]--------[End Turn]+
```

### Cross-Platform Considerations

1. **Touch vs Mouse**: Use `GestureDetector` for touch; add `MouseRegion` for hover effects on desktop/web.
2. **Right-click context menu**: Desktop web could show card details on right-click.
3. **Keyboard shortcuts**: Add keyboard shortcuts for desktop (spacebar = end turn, number keys = play card N).
4. **Text scaling**: Respect system font size preferences. Test with large text.
5. **Safe areas**: Use `SafeArea` widget for phones with notches/rounded corners.
6. **Web-specific**: Disable browser text selection on card text. Handle browser back button.

### State Management Recommendation

For a card game with complex state:
- **`riverpod`** (pub.dev): Recommended. Compile-safe, testable, scales well. Use `StateNotifier` or `Notifier` for game state.
- **`bloc`** (pub.dev): Also excellent. Event-driven, good for game actions (PlayCard, BuyCard, EndTurn events).
- **`provider`**: Simpler but sufficient for smaller scope.

---

## 11. Research Confidence

| Area | Confidence | Notes / Gaps |
|------|-----------|--------------|
| **Flutter card game packages** | **High** | Flame, flutter_animate, and built-in widgets are well-documented. No dedicated "deck-builder framework" exists -- you build from primitives. |
| **Card UI design patterns** | **High** | Star Realms app is the closest reference. Slay the Spire and Hearthstone patterns well understood. Consider playing Star Realms mobile app for direct reference. |
| **Free/open art assets** | **High** | Kenney.nl (CC0) and game-icons.net (CC-BY) are the strongest starting points. OpenGameArt has volume. For card art specifically, AI generation or commissioning will likely be needed. |
| **Icon libraries** | **High** | game-icons.net covers nearly all game concepts. flutter_svg handles SVG rendering. Material and Phosphor icons fill gaps. |
| **Card frame/template design** | **Medium** | Design approach is clear (widget composition vs CustomPainter vs pre-rendered). Gap: no specific free Fragments-of-Boundlessness-style card frame templates exist. Will need custom design work. |
| **Animation and polish** | **High** | flutter_animate + implicit animations cover most needs. Lottie/Rive for premium effects. Performance patterns well documented. |
| **Color palettes** | **High** | Hex codes provided for all 4 factions plus UI chrome. Based on the actual Fragments of Boundlessness faction identities. Fine-tune based on playtesting. |
| **Typography** | **High** | Google Fonts recommendations are concrete and tested. Orbitron + Inter is a strong combination for sci-fi card games. |
| **Sound effects** | **High** | Multiple free sources identified with URLs. Kenney and Freesound are the strongest. Flutter audio packages are mature. |
| **Responsive layout** | **High** | Breakpoints, layout strategies, and code patterns provided. Built-in Flutter responsive tools are sufficient. |

### Remaining Gaps / Future Research

1. **Multiplayer networking**: Not covered here. Research WebSocket libraries (shelf_web_socket, socket_io_client) and Firebase Realtime Database for game state sync.
2. **Accessibility**: Screen reader support for card games is an unsolved UX challenge. Research TalkBack/VoiceOver patterns for card games.
3. **Localization**: If the game will be translated, research `flutter_localizations` and text layout for different languages (card text expansion in German, RTL for Arabic, etc.).
4. **Performance profiling**: For 60fps on lower-end phones, research Flutter DevTools profiling and `RepaintBoundary` optimization.
5. **Card art pipeline**: Establish a workflow for creating/commissioning card art at consistent style and dimensions. Consider Midjourney or Stable Diffusion for rapid prototyping.
6. **Tutorial/onboarding UX**: Research coach marks (`tutorial_coach_mark` package) and interactive tutorials for teaching the game.
7. **Backend/persistence**: Local storage (`hive`, `shared_preferences`) for game state. Cloud save for cross-device play.

---

*Note: Web search and fetch tools were unavailable during research compilation. All information is based on established knowledge of Flutter ecosystem, game design patterns, and asset libraries. URLs and package names should be verified for current availability and version compatibility. Package maintenance status should be checked on pub.dev before adoption.*




