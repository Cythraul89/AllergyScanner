import 'package:drift/drift.dart';

import '../../models/enums.dart';
import 'products_table.dart';

/// Scan history (REQUIREMENTS §4.3).
///
/// [evaluatedText] and [productNameSnapshot] are snapshots on purpose: a stored
/// verdict must stay readable and unchanged after the product is corrected or
/// the matching rules change (doc/ARCHITECTURE.md §5.5).
@DataClassName('ScanRow')
class Scans extends Table {
  TextColumn get id => text()();

  DateTimeColumn get scannedAt => dateTime()();

  IntColumn get inputMode => intEnum<ScanInputMode>()();

  /// Nullable and `setNull`, so deleting a product keeps the scan readable.
  TextColumn get barcode => text()
      .nullable()
      .references(Products, #barcode, onDelete: KeyAction.setNull)();

  TextColumn get productNameSnapshot => text().nullable()();

  /// Exactly the text that was matched.
  TextColumn get evaluatedText => text()();

  IntColumn get verdict => intEnum<ScanVerdict>()();

  /// Denormalised count of the related `scan_matches` rows.
  IntColumn get matchCount => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
