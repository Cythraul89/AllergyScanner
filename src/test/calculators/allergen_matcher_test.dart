import 'package:allergy_scanner/core/calculators/allergen_matcher.dart';
import 'package:allergy_scanner/core/calculators/text_normalizer.dart';
import 'package:allergy_scanner/core/models/allergen_term.dart';
import 'package:allergy_scanner/core/models/enums.dart';
import 'package:flutter_test/flutter_test.dart';

/// Terms are built through the same normaliser the DAO uses, so a test can
/// never accidentally assert against a hand-written normalised form.
AllergenTerm term(String value) {
  final DateTime timestamp = DateTime.utc(2026, 1, 1);
  return AllergenTerm(
    id: 'id-$value',
    term: value,
    normalizedTerm: TextNormalizer.normalize(value),
    isActive: true,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

void main() {
  const String ingredients =
      'Sugar, cocoa butter, HAZELNUTS, skimmed MILK powder, '
      'soy lecithin (E322), natural vanilla flavouring';

  group('verdicts', () {
    test('a match yields hit', () {
      final MatchOutcome outcome = AllergenMatcher.match(
        text: ingredients,
        activeTerms: <AllergenTerm>[term('hazelnut')],
      );
      expect(outcome.verdict, ScanVerdict.hit);
      expect(outcome.matches, hasLength(1));
    });

    test('text present but nothing found yields noMatch — never "safe"', () {
      final MatchOutcome outcome = AllergenMatcher.match(
        text: ingredients,
        activeTerms: <AllergenTerm>[term('celery')],
      );
      expect(outcome.verdict, ScanVerdict.noMatch);
      expect(outcome.matches, isEmpty);
    });

    test('empty text yields unknown, not noMatch', () {
      final MatchOutcome outcome = AllergenMatcher.match(
        text: '   ,,,  ',
        activeTerms: <AllergenTerm>[term('milk')],
      );
      expect(outcome.verdict, ScanVerdict.unknown);
    });

    test('an empty term list yields unknown, not noMatch', () {
      final MatchOutcome outcome = AllergenMatcher.match(
        text: ingredients,
        activeTerms: const <AllergenTerm>[],
      );
      expect(outcome.verdict, ScanVerdict.unknown);
    });
  });

  group('matching', () {
    test('is case and punctuation insensitive', () {
      final MatchOutcome outcome = AllergenMatcher.match(
        text: ingredients,
        activeTerms: <AllergenTerm>[term('Soy Lecithin')],
      );
      expect(outcome.verdict, ScanVerdict.hit);
      expect(outcome.matches.single.term, 'Soy Lecithin');
    });

    test('is accent insensitive in both directions', () {
      expect(
        AllergenMatcher.match(
          text: 'farine, sésame, sel',
          activeTerms: <AllergenTerm>[term('sesame')],
        ).verdict,
        ScanVerdict.hit,
      );
      expect(
        AllergenMatcher.match(
          text: 'flour, sesame, salt',
          activeTerms: <AllergenTerm>[term('Sésame')],
        ).verdict,
        ScanVerdict.hit,
      );
    });

    test('finds a term written with the German sharp s', () {
      expect(
        AllergenMatcher.match(
          text: 'Zucker, Haselnuß, Kakao',
          activeTerms: <AllergenTerm>[term('haselnuss')],
        ).verdict,
        ScanVerdict.hit,
      );
    });

    test('matches across the newlines of recognised text', () {
      expect(
        AllergenMatcher.match(
          text: 'skimmed milk\npowder',
          activeTerms: <AllergenTerm>[term('milk powder')],
        ).verdict,
        ScanVerdict.hit,
      );
    });

    test('reports one match per term, ordered by offset', () {
      final MatchOutcome outcome = AllergenMatcher.match(
        text: ingredients,
        activeTerms: <AllergenTerm>[term('soy'), term('hazelnut')],
      );
      expect(outcome.matches.map((AllergenMatch m) => m.term).toList(), <String>[
        'hazelnut',
        'soy',
      ]);
      expect(
        outcome.matches.first.startOffset,
        lessThan(outcome.matches.last.startOffset),
      );
    });

    test('a term occurring several times is reported once', () {
      final MatchOutcome outcome = AllergenMatcher.match(
        text: 'milk, milk powder, milk fat',
        activeTerms: <AllergenTerm>[term('milk')],
      );
      expect(outcome.matches, hasLength(1));
      expect(outcome.matches.single.startOffset, 0);
    });

    test('offsets point into the normalised text', () {
      final MatchOutcome outcome = AllergenMatcher.match(
        text: ingredients,
        activeTerms: <AllergenTerm>[term('hazelnuts')],
      );
      final AllergenMatch match = outcome.matches.single;
      expect(
        outcome.normalizedText.substring(match.startOffset, match.endOffset),
        'hazelnuts',
      );
      expect(match.matchedText, 'hazelnuts');
    });

    test('inactive terms are the caller\'s responsibility, not the matcher\'s', () {
      // The matcher receives only active terms; passing an inactive one still
      // matches, which is why the DAO query filters instead.
      final AllergenTerm inactive = term('milk').copyWith(isActive: false);
      expect(
        AllergenMatcher.match(
          text: ingredients,
          activeTerms: <AllergenTerm>[inactive],
        ).verdict,
        ScanVerdict.hit,
      );
    });
  });

  group('accepted limitations — pinned so a change is deliberate', () {
    test('a short term matches inside a longer word (nut in coconut)', () {
      final MatchOutcome outcome = AllergenMatcher.match(
        text: 'coconut oil, butternut squash',
        activeTerms: <AllergenTerm>[term('nut')],
      );
      // False positive, accepted for v0.1 (doc/ARCHITECTURE.md §5.3). Word
      // boundaries would also lose "milk" inside "buttermilk".
      expect(outcome.verdict, ScanVerdict.hit);
    });

    test('substring matching finds a genuine compound (milk in buttermilk)', () {
      expect(
        AllergenMatcher.match(
          text: 'buttermilk powder',
          activeTerms: <AllergenTerm>[term('milk')],
        ).verdict,
        ScanVerdict.hit,
      );
    });

    test('a Latin name is not found unless it is listed', () {
      expect(
        AllergenMatcher.match(
          text: 'Corylus avellana',
          activeTerms: <AllergenTerm>[term('hazelnut')],
        ).verdict,
        ScanVerdict.noMatch,
      );
    });

    test('an E-number is not found unless it is listed', () {
      expect(
        AllergenMatcher.match(
          text: 'emulsifier (E322)',
          activeTerms: <AllergenTerm>[term('lecithin')],
        ).verdict,
        ScanVerdict.noMatch,
      );
    });

    test('a term below the minimum length is ignored entirely', () {
      final AllergenTerm tooShort = term('so');
      expect(TextNormalizer.isSearchable(tooShort.normalizedTerm), isFalse);
      expect(
        AllergenMatcher.match(
          text: ingredients,
          activeTerms: <AllergenTerm>[tooShort],
        ).verdict,
        ScanVerdict.noMatch,
      );
    });
  });

  group('contextFor', () {
    test('cuts an excerpt around the match and marks the cut', () {
      // 'hazelnuts' starts too close to the beginning of `ingredients` for a
      // leading cut to happen; 'lecithin' sits far enough from both ends.
      final MatchOutcome outcome = AllergenMatcher.match(
        text: ingredients,
        activeTerms: <AllergenTerm>[term('lecithin')],
      );
      final AllergenMatch match = outcome.matches.single;
      final String context = match.contextIn(outcome.normalizedText);
      expect(context, contains('lecithin'));
      expect(context.startsWith('…'), isTrue);
      expect(context.endsWith('…'), isTrue);
    });

    test('does not mark a cut it did not make', () {
      final MatchOutcome outcome = AllergenMatcher.match(
        text: 'milk',
        activeTerms: <AllergenTerm>[term('milk')],
      );
      expect(
        outcome.matches.single.contextIn(outcome.normalizedText),
        'milk',
      );
    });

    test('an empty text yields an empty context', () {
      expect(AllergenMatcher.contextFor('', 0, 0), '');
    });
  });
}
