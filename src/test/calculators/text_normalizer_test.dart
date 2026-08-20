import 'package:allergy_scanner/core/calculators/text_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TextNormalizer.normalize', () {
    test('lowercases', () {
      expect(TextNormalizer.normalize('HAZELNUTS'), 'hazelnuts');
    });

    test('folds Latin diacritics to the base letter', () {
      expect(TextNormalizer.normalize('Sésame'), 'sesame');
      expect(TextNormalizer.normalize('Nüsse'), 'nusse');
      expect(TextNormalizer.normalize('Créme brûlée'), 'creme brulee');
    });

    test('expands the German sharp s', () {
      expect(TextNormalizer.normalize('Nuß'), 'nuss');
    });

    test('expands ligatures', () {
      expect(TextNormalizer.normalize('Œuf'), 'oeuf');
      expect(TextNormalizer.normalize('Æbleskiver'), 'aebleskiver');
    });

    test('replaces punctuation with a single space', () {
      expect(
        TextNormalizer.normalize('sugar, cocoa butter (E322)*'),
        'sugar cocoa butter e322',
      );
    });

    test('flattens the newlines a photographed list is full of', () {
      expect(
        TextNormalizer.normalize('sugar,\ncocoa\r\nbutter'),
        'sugar cocoa butter',
      );
    });

    test('collapses whitespace runs and trims', () {
      expect(TextNormalizer.normalize('   milk    powder  '), 'milk powder');
    });

    test('keeps digits', () {
      expect(TextNormalizer.normalize('E 322'), 'e 322');
    });

    test('keeps non-Latin letters instead of destroying them', () {
      expect(TextNormalizer.normalize('молоко'), 'молоко');
    });

    test('an empty or punctuation-only input normalises to empty', () {
      expect(TextNormalizer.normalize(''), '');
      expect(TextNormalizer.normalize('  ,.-  '), '');
    });

    test('is idempotent — normalising twice changes nothing', () {
      const String input = 'Zucker, HASELNÜSSE (30 %), Sojalecithin';
      final String once = TextNormalizer.normalize(input);
      expect(TextNormalizer.normalize(once), once);
    });
  });

  group('TextNormalizer.isSearchable', () {
    test('rejects terms below the minimum length', () {
      expect(TextNormalizer.minimumTermLength, 3);
      expect(TextNormalizer.isSearchable('ab'), isFalse);
      expect(TextNormalizer.isSearchable('nut'), isTrue);
    });
  });
}
