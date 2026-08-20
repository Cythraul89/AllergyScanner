import 'package:drift/drift.dart';

import 'allergen_terms_table.dart';
import 'scans_table.dart';

/// One hit inside a scan (REQUIREMENTS §4.4).
@DataClassName('ScanMatchRow')
class ScanMatches extends Table {
  TextColumn get id => text()();

  /// Deleting a scan deletes its matches.
  TextColumn get scanId =>
      text().references(Scans, #id, onDelete: KeyAction.cascade)();

  /// Deleting a term must not delete history, so this is nullable and cleared
  /// instead — [termSnapshot] preserves what the user saw.
  TextColumn get allergenTermId => text()
      .nullable()
      .references(AllergenTerms, #id, onDelete: KeyAction.setNull)();

  TextColumn get termSnapshot => text()();

  TextColumn get matchedText => text()();

  /// Offsets into the normalised form of `scans.evaluated_text`.
  IntColumn get startOffset => integer()();
  IntColumn get endOffset => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
