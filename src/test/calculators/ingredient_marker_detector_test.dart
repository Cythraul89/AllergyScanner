import 'package:allergy_scanner/core/calculators/ingredient_marker_detector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('marker found', () {
    test('finds "Ingredients:" case-insensitively', () {
      final MarkerDetectionResult result = IngredientMarkerDetector.detect(
        'INGREDIENTS: sugar, hazelnuts',
      );
      expect(result, isA<MarkerFound>());
      expect((result as MarkerFound).matchedMarker, 'INGREDIENTS:');
    });

    test('finds "Zutaten:"', () {
      expect(
        IngredientMarkerDetector.detect('Zutaten: Zucker, Haselnüsse'),
        isA<MarkerFound>(),
      );
    });

    test('finds "Ingrédients:" with the accent', () {
      expect(
        IngredientMarkerDetector.detect('Ingrédients: sucre, noisettes'),
        isA<MarkerFound>(),
      );
    });

    test('finds the accent-free spelling of the French marker too', () {
      expect(
        IngredientMarkerDetector.detect('Ingredients: sucre, noisettes'),
        isA<MarkerFound>(),
      );
    });

    test('finds "Ingredienti:"', () {
      expect(
        IngredientMarkerDetector.detect('Ingredienti: zucchero, nocciole'),
        isA<MarkerFound>(),
      );
    });

    test('tolerates a space before the colon', () {
      expect(
        IngredientMarkerDetector.detect('Ingredients : sugar'),
        isA<MarkerFound>(),
      );
    });

    test('picks the earliest marker when several are present', () {
      final MarkerDetectionResult result = IngredientMarkerDetector.detect(
        'Ingredients: sugar. Zutaten: Zucker.',
      );
      expect((result as MarkerFound).matchedMarker, 'Ingredients:');
    });

    test('section text starts right after the colon, trimmed', () {
      final MarkerDetectionResult result = IngredientMarkerDetector.detect(
        'Ingredients:   sugar, hazelnuts',
      );
      expect((result as MarkerFound).sectionText, 'sugar, hazelnuts');
    });

    test('section text runs to the end of the field, including later lines', () {
      final MarkerDetectionResult result = IngredientMarkerDetector.detect(
        'Ingredients: sugar\nhazelnuts\nAllergens: nuts',
      );
      expect(
        (result as MarkerFound).sectionText,
        'sugar\nhazelnuts\nAllergens: nuts',
      );
    });
  });

  group('marker not found', () {
    test('empty text', () {
      expect(IngredientMarkerDetector.detect(''), isA<MarkerNotFound>());
    });

    test('text with no marker word at all', () {
      expect(
        IngredientMarkerDetector.detect('sugar, hazelnuts, milk'),
        isA<MarkerNotFound>(),
      );
    });

    test('marker word present without a colon', () {
      expect(
        IngredientMarkerDetector.detect('Ingredients sugar, hazelnuts'),
        isA<MarkerNotFound>(),
      );
    });
  });

  group('accepted limitations — pinned so a change is deliberate', () {
    test('OCR dropping the colon is not recovered', () {
      expect(
        IngredientMarkerDetector.detect('Ingredients sugar, hazelnuts'),
        isA<MarkerNotFound>(),
      );
    });

    test('OCR misreading the colon as a semicolon is not recovered', () {
      expect(
        IngredientMarkerDetector.detect('Ingredients; sugar, hazelnuts'),
        isA<MarkerNotFound>(),
      );
    });

    test('a marker split across a line break is not recovered', () {
      expect(
        IngredientMarkerDetector.detect('Ingre-\ndients: sugar'),
        isA<MarkerNotFound>(),
      );
    });

    test('a language outside the supported four is not recognised', () {
      expect(
        IngredientMarkerDetector.detect('Ingredientes: azúcar'),
        isA<MarkerNotFound>(),
      );
    });

    test(
      'the marker word mid-sentence still counts — structural, not '
      'semantic, detection',
      () {
        expect(
          IngredientMarkerDetector.detect(
            'See our Ingredients: policy for details',
          ),
          isA<MarkerFound>(),
        );
      },
    );
  });
}
