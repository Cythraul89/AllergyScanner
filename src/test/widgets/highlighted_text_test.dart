import 'package:allergy_scanner/core/widgets/highlighted_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
