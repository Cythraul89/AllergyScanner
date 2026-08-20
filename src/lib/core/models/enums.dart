/// Outcome of a check (REQUIREMENTS §5.6).
///
/// [noMatch] deliberately does not mean "safe" — see the UI wording rules.
enum ScanVerdict { hit, noMatch, unknown }

/// How the evaluated text reached the app.
enum ScanInputMode { barcode, ocr, manualText, manualBarcode }

/// Where a product's data originally came from.
enum ProductSource { openFoodFacts, manual }
