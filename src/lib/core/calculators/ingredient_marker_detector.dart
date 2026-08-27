/// Detects a localized "Ingredients:" header so a photo of the wrong panel
/// (nutrition table, allergen advice, marketing text) is not silently
/// evaluated as an ingredients list. Plain literal/regex search — no
/// language-model interpretation (§1.2).
class IngredientMarkerDetector {
  const IngredientMarkerDetector._();

  /// English, German, French (accent optional — OCR/typing often drops it),
  /// Italian. The colon is required: it is what turns a stray occurrence of
  /// the word into a genuine section header, and it is a one-keystroke fix
  /// in the always-editable field (R7.3).
  static final RegExp _markerPattern = RegExp(
    r'\b(?:ingredients|zutaten|ingr[ée]dients|ingredienti)\s*:',
    caseSensitive: false,
  );

  /// Scans [rawText] as typed/recognised — not normalised.
  /// `TextNormalizer.normalize` strips the colon and collapses newlines,
  /// both of which this rule needs, so normalisation only happens
  /// afterwards, for matching within the detected section.
  static MarkerDetectionResult detect(String rawText) {
    final RegExpMatch? match = _markerPattern.firstMatch(rawText);
    if (match == null) return const MarkerNotFound();
    return MarkerFound(
      matchedMarker: rawText.substring(match.start, match.end),
      sectionText: rawText.substring(match.end).trimLeft(),
    );
  }
}

sealed class MarkerDetectionResult {
  const MarkerDetectionResult();
}

final class MarkerFound extends MarkerDetectionResult {
  const MarkerFound({required this.matchedMarker, required this.sectionText});

  /// The literal marker text as found (original case), e.g. "Zutaten:".
  final String matchedMarker;

  /// From the end of the marker to the end of the field, left-trimmed. A
  /// display-only scope for the review-screen preview — the actual check
  /// always evaluates the full, unmodified text regardless of this section.
  final String sectionText;
}

final class MarkerNotFound extends MarkerDetectionResult {
  const MarkerNotFound();
}
