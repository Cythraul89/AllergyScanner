import 'package:allergy_scanner/core/calculators/spelling_variant.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SpellingVariant.asciiAlternative', () {
    test('substitutes ö/ä/ü/ß with their ASCII equivalents', () {
      expect(SpellingVariant.asciiAlternative('Rapsöl'), 'Rapsoel');
      expect(SpellingVariant.asciiAlternative('Käse'), 'Kaese');
      expect(SpellingVariant.asciiAlternative('Über'), 'Ueber');
      expect(SpellingVariant.asciiAlternative('Nuß'), 'Nuss');
    });

    test('substitutes every occurrence, not just the first', () {
      expect(SpellingVariant.asciiAlternative('Rübenöl'), 'Ruebenoel');
    });

    test('returns null when there is nothing to substitute', () {
      expect(SpellingVariant.asciiAlternative('Hazelnut'), isNull);
      expect(SpellingVariant.asciiAlternative(''), isNull);
    });

    test('leaves other diacritics untouched', () {
      // Only the German substitutes are offered — not a general transliteration.
      expect(SpellingVariant.asciiAlternative('Sésame'), isNull);
    });
  });
}
