import 'package:drift/drift.dart';

/// The user's allergy list (REQUIREMENTS §4.1).
@DataClassName('AllergenTermRow')
class AllergenTerms extends Table {
  TextColumn get id => text()();

  /// Exactly as the user typed it — this is what the UI shows.
  TextColumn get term => text().withLength(min: 1, max: 200)();

  /// `TextNormalizer.normalize(term)`. The matcher reads only this column, and
  /// uniqueness is enforced on it so two spellings of the same term cannot both
  /// exist. Changing the normalisation rules therefore requires a migration
  /// that recomputes this column.
  TextColumn get normalizedTerm => text().unique()();

  /// Inactive terms are kept but not matched.
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  TextColumn get note => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
