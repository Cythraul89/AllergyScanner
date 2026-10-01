/// Outcome of a check (REQUIREMENTS §5.6).
///
/// [noMatch] deliberately does not mean "safe" — see the UI wording rules.
enum ScanVerdict { hit, noMatch, unknown }

/// How the evaluated text reached the app.
enum ScanInputMode { barcode, ocr, manualText, manualBarcode }

/// Where a product's data originally came from.
enum ProductSource { openFoodFacts, manual }

/// An optional, user-assigned severity tag on an allergen group. Deliberately
/// a plain relative scale (not clinical wording like "anaphylaxis risk") —
/// consistent with this app never making a safety/medical assessment
/// (REQUIREMENTS §5.6).
enum GroupCriticality { low, medium, high }
