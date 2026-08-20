/// The single normalisation used by the matcher, by the duplicate check when a
/// term is added, and by the stored `allergen_terms.normalized_term` column.
///
/// Two implementations that drift apart would make terms silently stop
/// matching — which in this app looks exactly like "no allergen found". Never
/// inline a second one; see doc/ARCHITECTURE.md §5.1.
///
/// Steps (REQUIREMENTS §5.2), in this order:
///   1. lowercase,
///   2. fold Latin diacritics to their base letter (`ä` → `a`) and the German
///      sharp s to `ss`,
///   3. replace every character that is neither a letter nor a digit with a
///      space — this removes the `(`, `)`, `,`, `*`, `-`, `.` and the newlines
///      that a photographed ingredient list is full of,
///   4. collapse whitespace runs and trim.
///
/// Known limitation: folding is to the *base letter*, not the German
/// transliteration. `Nüsse` becomes `nusse`, not `nuesse`, so a term typed as
/// "Nuesse" does not match "Nüsse". Type the umlaut form, or add both terms.
class TextNormalizer {
  const TextNormalizer._();

  /// Shortest normalised term the app accepts (REQUIREMENTS R5.5). Below this,
  /// substring matching produces noise rather than information.
  static const int minimumTermLength = 3;

  /// Keys are lowercase; [normalize] lowercases before looking them up.
  static const Map<String, String> _foldings = <String, String>{
    'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ā': 'a',
    'ă': 'a', 'ą': 'a',
    'æ': 'ae',
    'ç': 'c', 'ć': 'c', 'ĉ': 'c', 'ċ': 'c', 'č': 'c',
    'ď': 'd', 'đ': 'd', 'ð': 'd',
    'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e', 'ĕ': 'e', 'ė': 'e',
    'ę': 'e', 'ě': 'e',
    'ĝ': 'g', 'ğ': 'g', 'ġ': 'g', 'ģ': 'g',
    'ĥ': 'h', 'ħ': 'h',
    'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ĩ': 'i', 'ī': 'i', 'ĭ': 'i',
    'į': 'i', 'ı': 'i',
    'ĵ': 'j',
    'ķ': 'k',
    'ĺ': 'l', 'ļ': 'l', 'ľ': 'l', 'ŀ': 'l', 'ł': 'l',
    'ñ': 'n', 'ń': 'n', 'ņ': 'n', 'ň': 'n', 'ŋ': 'n',
    'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o', 'ō': 'o',
    'ŏ': 'o', 'ő': 'o',
    'œ': 'oe',
    'ŕ': 'r', 'ŗ': 'r', 'ř': 'r',
    'ś': 's', 'ŝ': 's', 'ş': 's', 'š': 's', 'ș': 's',
    'ß': 'ss',
    'ţ': 't', 'ť': 't', 'ŧ': 't', 'ț': 't',
    'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ũ': 'u', 'ū': 'u', 'ŭ': 'u',
    'ů': 'u', 'ű': 'u', 'ų': 'u',
    'ŵ': 'w',
    'ý': 'y', 'ÿ': 'y', 'ŷ': 'y',
    'ź': 'z', 'ż': 'z', 'ž': 'z',
    'þ': 'th',
  };

  /// Letters and digits of any script are kept; everything else becomes a
  /// space. Non-Latin scripts therefore survive matching unfolded.
  static final RegExp _keepPattern = RegExp(r'[\p{L}\p{N}]', unicode: true);
  static final RegExp _whitespaceRun = RegExp(r'\s+');

  static String normalize(String input) {
    final String lowercased = input.toLowerCase();
    final StringBuffer buffer = StringBuffer();
    for (final int rune in lowercased.runes) {
      final String character = String.fromCharCode(rune);
      final String? folded = _foldings[character];
      if (folded != null) {
        buffer.write(folded);
      } else if (_keepPattern.hasMatch(character)) {
        buffer.write(character);
      } else {
        buffer.write(' ');
      }
    }
    return buffer.toString().replaceAll(_whitespaceRun, ' ').trim();
  }

  /// Whether a term is long enough to be searched for.
  static bool isSearchable(String normalizedTerm) =>
      normalizedTerm.length >= minimumTermLength;
}
