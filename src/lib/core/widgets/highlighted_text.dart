import 'package:flutter/material.dart';

/// One `[start, end)` span of [HighlightedText.text] to mark.
class TextHighlightRange {
  const TextHighlightRange({
    required this.start,
    required this.end,
    this.label,
    this.color,
  });

  final int start;
  final int end;

  /// Unused for rendering today — carried through for a future tooltip.
  final String? label;

  /// Background to mark this span with — the colour of the allergen group the
  /// matched term belongs to (R7.16). `null` falls back to the theme's error
  /// container, which is what every match looked like before groups could
  /// carry a colour.
  final Color? color;
}

/// Renders [text] with [highlights] shown inline, bold plus a background
/// tint — never colour alone (R7.4), so a group colour only ever adds
/// information and never becomes the sole carrier of "this is a match".
class HighlightedText extends StatelessWidget {
  const HighlightedText({
    required this.text,
    required this.highlights,
    this.style,
    super.key,
  });

  final String text;
  final List<TextHighlightRange> highlights;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextStyle base = style ?? DefaultTextStyle.of(context).style;
    final List<({String text, bool highlighted, Color? color})> segments =
        resolveHighlightSegments(text, highlights);
    return SelectableText.rich(
      TextSpan(
        children: <InlineSpan>[
          for (final ({String text, bool highlighted, Color? color}) segment
              in segments)
            TextSpan(
              text: segment.text,
              style: segment.highlighted
                  ? base.copyWith(
                      fontWeight: FontWeight.bold,
                      backgroundColor: segment.color ?? scheme.errorContainer,
                      color: segment.color == null
                          ? scheme.onErrorContainer
                          : foregroundOn(segment.color!),
                    )
                  : base,
            ),
        ],
      ),
    );
  }
}

/// Black or white, whichever stays readable on [background].
///
/// A group colour is picked from a fixed palette that spans very light
/// (amber) to very dark (indigo), so a single fixed foreground would be
/// illegible on one end of it.
@visibleForTesting
Color foregroundOn(Color background) =>
    ThemeData.estimateBrightnessForColor(background) == Brightness.dark
    ? Colors.white
    : Colors.black;

/// Splits [text] into alternating highlighted/unhighlighted segments from
/// [ranges]. Pure so it is unit-testable without a widget pump.
///
/// Ranges are clamped into `[0, text.length]`, sorted, and any range
/// overlapping an already-accepted one is dropped rather than rendered —
/// `AllergenMatcher.match` returns one match per *term* and was designed for
/// a UI that shows each match on its own line, so it never had to guard
/// against overlaps between different terms (e.g. "milk" inside "milk
/// powder"). Inline rendering is the first place that can actually break.
@visibleForTesting
List<({String text, bool highlighted, Color? color})> resolveHighlightSegments(
  String text,
  List<TextHighlightRange> ranges,
) {
  final List<TextHighlightRange> clamped = ranges
      .map(
        (TextHighlightRange r) => TextHighlightRange(
          start: r.start.clamp(0, text.length),
          end: r.end.clamp(0, text.length),
          color: r.color,
        ),
      )
      .where((TextHighlightRange r) => r.end > r.start)
      .toList()
    ..sort((TextHighlightRange a, TextHighlightRange b) => a.start.compareTo(b.start));

  final List<TextHighlightRange> accepted = <TextHighlightRange>[];
  for (final TextHighlightRange range in clamped) {
    if (accepted.isNotEmpty && range.start < accepted.last.end) continue;
    accepted.add(range);
  }

  final List<({String text, bool highlighted, Color? color})> segments =
      <({String text, bool highlighted, Color? color})>[];
  int cursor = 0;
  for (final TextHighlightRange range in accepted) {
    if (range.start > cursor) {
      segments.add((
        text: text.substring(cursor, range.start),
        highlighted: false,
        color: null,
      ));
    }
    segments.add((
      text: text.substring(range.start, range.end),
      highlighted: true,
      color: range.color,
    ));
    cursor = range.end;
  }
  if (cursor < text.length) {
    segments.add((
      text: text.substring(cursor),
      highlighted: false,
      color: null,
    ));
  }
  if (segments.isEmpty) {
    segments.add((text: text, highlighted: false, color: null));
  }
  return segments;
}
