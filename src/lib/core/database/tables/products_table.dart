import 'package:drift/drift.dart';

import '../../models/enums.dart';

/// Open Food Facts cache and local corrections (REQUIREMENTS §4.2).
@DataClassName('ProductRow')
class Products extends Table {
  /// EAN-8/13, UPC-A/E or GTIN-14 as the scanner reported it.
  TextColumn get barcode => text()();

  TextColumn get productName => text().nullable()();
  TextColumn get brands => text().nullable()();
  TextColumn get quantity => text().nullable()();

  /// The text the matcher evaluates.
  TextColumn get ingredientsText => text().nullable()();

  /// Language tag of [ingredientsText], shown in the result view so the user
  /// can tell that an English list was matched against German terms.
  TextColumn get ingredientsLanguage => text().nullable()();

  /// Newline-separated Open Food Facts tags. Displayed, never matched.
  TextColumn get allergensTags => text().nullable()();
  TextColumn get tracesTags => text().nullable()();

  /// Not downloaded in v0.1.
  TextColumn get imageUrl => text().nullable()();

  IntColumn get source => intEnum<ProductSource>()();

  /// A corrected row is never overwritten by a fetch and never counts as stale.
  BoolColumn get hasManualOverride =>
      boolean().withDefault(const Constant(false))();

  DateTimeColumn get fetchedAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {barcode};
}
