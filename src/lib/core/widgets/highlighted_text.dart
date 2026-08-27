import 'package:flutter/material.dart';

/// One `[start, end)` span of [HighlightedText.text] to mark.
class TextHighlightRange {
  const TextHighlightRange({required this.start, required this.end, this.label});

  final int start;
  final int end;

  /// Unused for rendering today — carried through for a future tooltip.
  final String? label;
}

/// Renders [text] with [highlights] shown inline, bold plus a background
/// tint — never colour alone (R7.4). The first `RichText`/`TextSpan`
/// highlighting in this codebase; `scan_result_screen.dart` only ever shows
/// separate plain-text context excerpts.
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
    final TextStyle base = style ?? DefaultTextStyle.of(context).style;
    final TextStyle highlightStyle = base.copyWith(
      fontWeight: FontWeight.bold,
      backgroundColor: Theme.of(context).colorScheme.errorContainer,
      color: Theme.of(context).colorScheme.onErrorContainer,
    );
    final List<({String text, bool highlighted})> segments =
        resolveHighlightSegments(text, highlights);
    return SelectableText.rich(
      TextSpan(
        children: <InlineSpan>[
          for (final ({String text, bool highlighted}) segment in segments)
            TextSpan(
              text: segment.text,
              style: segment.highlighted ? highlightStyle : base,
            ),
        ],
      ),
    );
  }
}

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
List<({String text, bool highlighted})> resolveHighlightSegments(
  String text,
  List<TextHighlightRange> ranges,
) {
  final List<TextHighlightRange> clamped = ranges
      .map(
        (TextHighlightRange r) => TextHighlightRange(
          start: r.start.clamp(0, text.length),
          end: r.end.clamp(0, text.length),
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

  final List<({String text, bool highlighted})> segments =
      <({String text, bool highlighted})>[];
  int cursor = 0;
  for (final TextHighlightRange range in accepted) {
    if (range.start > cursor) {
      segments.add((
        text: text.substring(cursor, range.start),
        highlighted: false,
      ));
    }
    segments.add((
      text: text.substring(range.start, range.end),
      highlighted: true,
    ));
    cursor = range.end;
  }
  if (cursor < text.length) {
    segments.add((text: text.substring(cursor), highlighted: false));
  }
  if (segments.isEmpty) {
    segments.add((text: text, highlighted: false));
  }
  return segments;
}
