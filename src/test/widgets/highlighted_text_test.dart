import 'package:allergy_scanner/core/widgets/highlighted_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('group colours', () {
    test('a range carries its colour onto the highlighted segment only', () {
      final segments = resolveHighlightSegments(
        'sugar, hazelnuts, milk',
        const <TextHighlightRange>[
          TextHighlightRange(start: 7, end: 16, color: Colors.red),
        ],
      );
      expect(segments.map((s) => s.color), <Color?>[null, Colors.red, null]);
    });

    test('two matches keep their own colours', () {
      final segments = resolveHighlightSegments(
        'milk and nuts',
        const <TextHighlightRange>[
          TextHighlightRange(start: 0, end: 4, color: Colors.blue),
          TextHighlightRange(start: 9, end: 13, color: Colors.green),
        ],
      );
      final highlighted = segments.where((s) => s.highlighted).toList();
      expect(highlighted.map((s) => s.text), <String>['milk', 'nuts']);
      expect(highlighted.map((s) => s.color), <Color?>[
        Colors.blue,
        Colors.green,
      ]);
    });

    test('a match whose group has no colour stays null (theme fallback)', () {
      final segments = resolveHighlightSegments(
        'milk',
        const <TextHighlightRange>[TextHighlightRange(start: 0, end: 4)],
      );
      expect(segments.single.highlighted, isTrue);
      expect(segments.single.color, isNull);
    });

    test('foregroundOn picks a readable contrast for both ends of the palette',
        () {
      // Amber is light, indigo is dark — a single fixed foreground would be
      // illegible on one of them.
      expect(foregroundOn(Colors.amber), Colors.black);
      expect(foregroundOn(Colors.indigo), Colors.white);
    });
  });

  group('HighlightedText rendering', () {
    /// Collects the styled spans the widget actually built, so this covers the
    /// step resolveHighlightSegments cannot: that a group colour reaches the
    /// painted TextSpan.
    List<TextSpan> spansOf(WidgetTester tester) {
      final SelectableText widget = tester.widget<SelectableText>(
        find.byType(SelectableText),
      );
      return (widget.textSpan!.children ?? const <InlineSpan>[])
          .cast<TextSpan>()
          .toList();
    }

    testWidgets('a group colour becomes the span background', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HighlightedText(
              text: 'sugar, hazelnuts, milk',
              highlights: <TextHighlightRange>[
                TextHighlightRange(start: 7, end: 16, color: Colors.indigo),
              ],
            ),
          ),
        ),
      );

      final List<TextSpan> spans = spansOf(tester);
      final TextSpan match = spans.firstWhere((s) => s.text == 'hazelnuts');
      expect(match.style?.backgroundColor, Colors.indigo);
      expect(match.style?.color, Colors.white, reason: 'readable on indigo');
      // Colour must never be the only signal that this is a match (R7.4).
      expect(match.style?.fontWeight, FontWeight.bold);

      final TextSpan plain = spans.firstWhere((s) => s.text == 'sugar, ');
      expect(plain.style?.backgroundColor, isNull);
    });

    testWidgets('without a group colour it falls back to the error container',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HighlightedText(
              text: 'milk and nuts',
              highlights: <TextHighlightRange>[
                TextHighlightRange(start: 0, end: 4),
              ],
            ),
          ),
        ),
      );

      final BuildContext context = tester.element(find.byType(HighlightedText));
      final ColorScheme scheme = Theme.of(context).colorScheme;
      final TextSpan match = spansOf(
        tester,
      ).firstWhere((s) => s.text == 'milk');
      expect(match.style?.backgroundColor, scheme.errorContainer);
      expect(match.style?.color, scheme.onErrorContainer);
    });
  });

  group('resolveHighlightSegments', () {
    test('no ranges yields one unhighlighted segment', () {
      final segments = resolveHighlightSegments('sugar, hazelnuts', const []);
      expect(segments, hasLength(1));
      expect(segments.single.text, 'sugar, hazelnuts');
      expect(segments.single.highlighted, isFalse);
    });

    test('a single range splits into before/highlight/after', () {
      final segments = resolveHighlightSegments(
        'sugar, hazelnuts, milk',
        const [TextHighlightRange(start: 7, end: 16)],
      );
      expect(segments.map((s) => s.text), <String>[
        'sugar, ',
        'hazelnuts',
        ', milk',
      ]);
      expect(segments.map((s) => s.highlighted), <bool>[false, true, false]);
    });

    test('adjacent ranges at the very start/end of text', () {
      final segments = resolveHighlightSegments(
        'milk',
        const [TextHighlightRange(start: 0, end: 4)],
      );
      expect(segments, hasLength(1));
      expect(segments.single.text, 'milk');
      expect(segments.single.highlighted, isTrue);
    });

    test('a range clamped when it runs past the end of the text', () {
      final segments = resolveHighlightSegments(
        'milk',
        const [TextHighlightRange(start: 2, end: 100)],
      );
      expect(segments.last.text, 'lk');
      expect(segments.last.highlighted, isTrue);
    });

    test('an out-of-order range list is sorted before rendering', () {
      final segments = resolveHighlightSegments(
        'aaa bbb ccc',
        const [
          TextHighlightRange(start: 8, end: 11),
          TextHighlightRange(start: 0, end: 3),
        ],
      );
      expect(segments.map((s) => s.text), <String>[
        'aaa',
        ' bbb ',
        'ccc',
      ]);
    });

    test('an overlapping range is dropped, not rendered garbled', () {
      // "milk" inside "milk powder" — both terms active.
      final segments = resolveHighlightSegments(
        'milk powder',
        const [
          TextHighlightRange(start: 0, end: 4), // "milk"
          TextHighlightRange(start: 0, end: 11), // "milk powder"
        ],
      );
      expect(segments.map((s) => s.text).join(), 'milk powder');
      // Only the first-accepted (earliest-sorted, then first of ties) range
      // survives; the overlapping second range is dropped rather than
      // corrupting the segment boundaries.
      expect(segments.where((s) => s.highlighted), hasLength(1));
    });
  });
}
