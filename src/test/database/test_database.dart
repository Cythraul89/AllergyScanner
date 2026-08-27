import 'package:allergy_scanner/core/database/app_database.dart';
import 'package:allergy_scanner/core/models/allergen_term.dart';
import 'package:allergy_scanner/core/models/enums.dart';
import 'package:allergy_scanner/core/models/product.dart';
import 'package:allergy_scanner/core/models/scan.dart';
import 'package:drift/native.dart';

/// In-memory database for DAO tests. Foreign keys are enabled by the
/// `beforeOpen` step of the real migration strategy, so cascade and setNull
/// behave here exactly as on a device.
AppDatabase openTestDatabase() =>
    AppDatabase.forTesting(NativeDatabase.memory());

final DateTime testTimestamp = DateTime.utc(2026, 8, 20, 12);

AllergenTerm buildTerm({
  required String id,
  required String term,
  required String normalizedTerm,
  bool isActive = true,
  String? note,
  String? groupId,
}) {
  return AllergenTerm(
    id: id,
    term: term,
    normalizedTerm: normalizedTerm,
    isActive: isActive,
    note: note,
    groupId: groupId,
    createdAt: testTimestamp,
    updatedAt: testTimestamp,
  );
}

Product buildProduct({
  required String barcode,
  String? productName = 'Choco Bar',
  String? ingredientsText = 'sugar, hazelnuts, milk',
  ProductSource source = ProductSource.openFoodFacts,
  bool hasManualOverride = false,
  DateTime? fetchedAt,
}) {
  return Product(
    barcode: barcode,
    productName: productName,
    ingredientsText: ingredientsText,
    allergensTags: const <String>['en:nuts', 'en:milk'],
    tracesTags: const <String>['en:gluten'],
    source: source,
    hasManualOverride: hasManualOverride,
    fetchedAt: fetchedAt ?? testTimestamp,
    updatedAt: testTimestamp,
  );
}

Scan buildScan({
  required String id,
  DateTime? scannedAt,
  String? barcode,
  ScanVerdict verdict = ScanVerdict.hit,
  int matchCount = 1,
  String evaluatedText = 'sugar, hazelnuts, milk',
  ScanInputMode inputMode = ScanInputMode.barcode,
  String? name,
  String? shop,
  String? photoPath,
}) {
  return Scan(
    id: id,
    scannedAt: scannedAt ?? testTimestamp,
    inputMode: inputMode,
    barcode: barcode,
    productNameSnapshot: 'Choco Bar',
    evaluatedText: evaluatedText,
    verdict: verdict,
    matchCount: matchCount,
    name: name,
    shop: shop,
    photoPath: photoPath,
  );
}

ScanMatch buildMatch({
  required String id,
  required String scanId,
  String? allergenTermId,
  String termSnapshot = 'hazelnut',
}) {
  return ScanMatch(
    id: id,
    scanId: scanId,
    allergenTermId: allergenTermId,
    termSnapshot: termSnapshot,
    matchedText: 'hazelnut',
    startOffset: 7,
    endOffset: 15,
  );
}
