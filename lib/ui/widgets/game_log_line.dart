import 'package:flutter/material.dart';

import 'resource_icons.dart';

/// A structured resource quantity attached to a log entry (the engine's
/// `LogResourceGrant`), rendered as an inline icon in [GameLogLine].
@immutable
class LogGrant {
  const LogGrant(this.kind, this.amount);

  /// One of `gem` / `power` / `mastery` / `health` (the engine's grant kinds).
  final String kind;
  final int amount;

  /// Parse the redacted view's raw `grants` list (a `List<Map<String,dynamic>>`
  /// of `{kind, amount}`) into [LogGrant]s. Non-map / malformed entries are
  /// skipped, so a bad payload never throws — it just shows fewer icons.
  static List<LogGrant> fromRaw(Object? raw) {
    if (raw is! List) return const [];
    final out = <LogGrant>[];
    for (final g in raw) {
      if (g is! Map) continue;
      final kind = g['kind'] as String?;
      final amount = g['amount'] as int?;
      if (kind == null || amount == null || amount <= 0) continue;
      out.add(LogGrant(kind, amount));
    }
    return out;
  }
}

/// The ONE shared renderer for a game action-log line, used by BOTH the
/// networked board's Log sheet and the local board so they can never diverge.
///
/// It turns a log entry into a single INLINE [Text.rich] run (never a forced
/// newline): the actor's name, the message text, and any resource icons all
/// flow on the same line and wrap naturally.
///
/// Two classes of resource reference become inline [ResourceIconWidget]s:
///  1. **Structured grants** (`grants`) — a played/activated card's flat gains,
///     shown as `N×<icon>` after the message.
///  2. **Resource WORDS inside the message** — the engine phrases a recruit /
///     fast-play COST as "for N gems" and Focus as "N gem → N mastery". A
///     bounded tokenizer (a closed set of words: `gem(s)` / `power` / `mastery`
///     / `health`) rewrites each `N <word>` to `N×<icon>` — so the cost and the
///     Focus trade render as icons, not the literal word. This is a deliberate,
///     documented tokenizer over ENGINE-controlled phrasing (not free text), so
///     it is robust; unrecognised text is passed through verbatim.
///
/// **Player names.** The actor (`actorId`) and any player referenced INSIDE the
/// message are engine SEAT IDS (`p0`). [nameOf] resolves a seat id to a display
/// name — the lobby username on the networked board, `PlayerState.name` on the
/// local board — so every player reference reads as a real name. (On the
/// networked board the server already rewrites embedded seat ids to usernames,
/// so the message tokenizer usually finds none left to resolve; resolving again
/// is a harmless no-op. The actor prefix is always resolved here.)
class GameLogLine extends StatelessWidget {
  const GameLogLine({
    super.key,
    required this.message,
    required this.nameOf,
    this.actorId,
    this.grants = const [],
    this.textStyle,
    this.iconSize = 13,
  });

  /// The engine log entry's `message` (verb-first, e.g. "played Crystal").
  final String message;

  /// The entry's `playerId` (actor seat id), or null for actor-less system
  /// events (turn header / win) whose subject is embedded in the message.
  final String? actorId;

  /// Structured resource gains to show after the message text.
  final List<LogGrant> grants;

  /// Resolves an engine seat id (`p0`) to a display name.
  final String Function(String seatId) nameOf;

  final TextStyle? textStyle;
  final double iconSize;

  static ResourceIcon? _iconFor(String kind) {
    switch (kind) {
      case 'gem':
        return ResourceIcon.gem;
      case 'power':
        return ResourceIcon.power;
      case 'mastery':
        return ResourceIcon.mastery;
      case 'health':
        return ResourceIcon.health;
      default:
        return null;
    }
  }

  static String _normalizeKind(String word) =>
      word == 'gems' ? 'gem' : word;

  // Matches EITHER a resource quantity ("4 gems", "1 mastery") OR a standalone
  // engine seat id ("p0"). Seat ids are word-boundary matched so an id embedded
  // in another token is never swapped.
  static final RegExp _token = RegExp(
    r'(\d+)\s+(gems?|power|mastery|health)\b'
    r'|(?<![A-Za-z0-9])(p\d+)(?![A-Za-z0-9])',
  );

  /// Build the inline span for a resource quantity: `N×<icon>` (or just the
  /// icon when N == 1, so a 1-cost / Focus trade reads cleanly).
  List<InlineSpan> _quantitySpans(int amount, String kind) {
    final icon = _iconFor(kind);
    if (icon == null) {
      // Unknown kind — fall back to the literal text so nothing is lost.
      return [TextSpan(text: '$amount $kind')];
    }
    return [
      if (amount != 1) TextSpan(text: '$amount×'),
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: ResourceIconWidget(icon, size: iconSize),
        ),
      ),
    ];
  }

  List<InlineSpan> _messageSpans() {
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _token.allMatches(message)) {
      if (m.start > last) {
        spans.add(TextSpan(text: message.substring(last, m.start)));
      }
      if (m.group(2) != null) {
        // Resource quantity.
        spans.addAll(
            _quantitySpans(int.parse(m.group(1)!), _normalizeKind(m.group(2)!)));
      } else {
        // Seat id → resolved display name.
        spans.add(TextSpan(text: nameOf(m.group(3)!)));
      }
      last = m.end;
    }
    if (last < message.length) {
      spans.add(TextSpan(text: message.substring(last)));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final base = textStyle ??
        const TextStyle(color: Color(0xFFE8EEF4), fontSize: 13, height: 1.3);

    final children = <InlineSpan>[];

    final actorName = actorId == null ? '' : nameOf(actorId!);
    if (actorName.isNotEmpty) {
      children.add(TextSpan(
          text: '$actorName ',
          style: const TextStyle(fontWeight: FontWeight.w600)));
    }

    children.addAll(_messageSpans());

    for (final g in grants) {
      children.add(const TextSpan(text: ' '));
      children.addAll(_quantitySpans(g.amount, g.kind));
    }

    return Text.rich(TextSpan(style: base, children: children));
  }
}
