/// Suggests the ASCII-substitute spelling of German umlauts and the sharp s
/// — a common alternative writing on packaging, in older data feeds and on
/// keyboards without those characters (`ö` → `oe`, `ä` → `ae`, `ü` → `ue`,
/// `ß` → `ss`).
///
/// This exists because of a documented limitation of [TextNormalizer]: its
/// diacritic folding maps to the *base letter* (`ö` → `o`), not this
/// transliteration, so "Rapsöl" and "Rapsoel" normalise differently and do
/// not match each other as one term — see `TextNormalizer`'s own doc comment
/// and REQUIREMENTS §5.4. That normalisation is deliberately left alone (it
/// is the one function every stored term and the matcher both depend on);
/// this is a separate, opt-in *suggestion* of a second spelling to add as
/// its own term, not a change to what already matches.
class SpellingVariant {
  const SpellingVariant._();

  static const Map<String, String> _asciiSubstitutes = <String, String>{
    'ä': 'ae', 'Ä': 'Ae',
    'ö': 'oe', 'Ö': 'Oe',
    'ü': 'ue', 'Ü': 'Ue',
    'ß': 'ss',
  };

  /// The ASCII-substitute spelling of [term], or `null` if it contains none
  /// of ä/ö/ü/ß (nothing to suggest).
  static String? asciiAlternative(String term) {
    bool changed = false;
    final StringBuffer buffer = StringBuffer();
    for (final int rune in term.runes) {
      final String character = String.fromCharCode(rune);
      final String? substitute = _asciiSubstitutes[character];
      if (substitute != null) {
        buffer.write(substitute);
        changed = true;
      } else {
        buffer.write(character);
      }
    }
    return changed ? buffer.toString() : null;
  }
}
