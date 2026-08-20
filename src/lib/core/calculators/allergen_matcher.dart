import '../models/allergen_term.dart';
import '../models/enums.dart';
import 'text_normalizer.dart';

/// Pure matching: models in, result out. No I/O, no logging, no clock.
///
/// The rule is deliberately plain substring matching on normalised text
/// (doc/ARCHITECTURE.md §5.3). Its accepted consequences — Latin names and
/// E-numbers are missed, `nut` is found inside `coconut` — are covered by tests
/// so that changing either is a deliberate act.
class AllergenMatcher {
  const AllergenMatcher._();

  /// Characters of context shown around a match in the result view (R5.6).
  static const int contextRadius = 24;

  static MatchOutcome match({
    required String text,
    required List<AllergenTerm> activeTerms,
  }) {
    final String normalizedText = TextNormalizer.normalize(text);

    // No text to check is not the same as nothing found (REQUIREMENTS §5.6).
    if (normalizedText.isEmpty) {
      return MatchOutcome(
        verdict: ScanVerdict.unknown,
        normalizedText: normalizedText,
        matches: const [],
      );
    }

    // An empty list would otherwise report "nothing found", which reads as an
    // all-clear the app has not earned (R5.7).
    if (activeTerms.isEmpty) {
      return MatchOutcome(
        verdict: ScanVerdict.unknown,
        normalizedText: normalizedText,
        matches: const [],
      );
    }

    final List<AllergenMatch> matches = <AllergenMatch>[];
    for (final AllergenTerm term in activeTerms) {
      final String needle = term.normalizedTerm;
      if (!TextNormalizer.isSearchable(needle)) continue;

      // First occurrence only: one entry per term is what the result view
      // shows, and a term repeated in an ingredient list adds no information.
      final int index = normalizedText.indexOf(needle);
      if (index < 0) continue;

      matches.add(
        AllergenMatch(
          termId: term.id,
          term: term.term,
          matchedText: normalizedText.substring(index, index + needle.length),
          startOffset: index,
          endOffset: index + needle.length,
        ),
      );
    }

    matches.sort((a, b) => a.startOffset.compareTo(b.startOffset));

    return MatchOutcome(
      verdict: matches.isEmpty ? ScanVerdict.noMatch : ScanVerdict.hit,
      normalizedText: normalizedText,
      matches: matches,
    );
  }

  /// Text around [startOffset]–[endOffset] of an already normalised text, with
  /// an ellipsis where it was cut. Used for both fresh and stored matches.
  static String contextFor(
    String normalizedText,
    int startOffset,
    int endOffset, {
    int radius = contextRadius,
  }) {
    if (normalizedText.isEmpty) return '';
    final int from = (startOffset - radius).clamp(0, normalizedText.length);
    final int to = (endOffset + radius).clamp(0, normalizedText.length);
    final String excerpt = normalizedText.substring(from, to);
    final String prefix = from > 0 ? '…' : '';
    final String suffix = to < normalizedText.length ? '…' : '';
    return '$prefix$excerpt$suffix';
  }
}

/// Result of one matching run.
class MatchOutcome {
  const MatchOutcome({
    required this.verdict,
    required this.normalizedText,
    required this.matches,
  });

  final ScanVerdict verdict;

  /// The text the offsets in [matches] refer to. Highlighting works on this
  /// string, so a highlight cannot drift out of sync with the raw input.
  final String normalizedText;

  final List<AllergenMatch> matches;
}

/// One term found in the text.
class AllergenMatch {
  const AllergenMatch({
    required this.termId,
    required this.term,
    required this.matchedText,
    required this.startOffset,
    required this.endOffset,
  });

  final String termId;

  /// As the user typed it — that is what the result view shows.
  final String term;
  final String matchedText;
  final int startOffset;
  final int endOffset;

  String contextIn(String normalizedText, {int radius = AllergenMatcher.contextRadius}) =>
      AllergenMatcher.contextFor(
        normalizedText,
        startOffset,
        endOffset,
        radius: radius,
      );
}
