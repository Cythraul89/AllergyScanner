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

  /// User-entered custom label, set after the fact via "Edit details" —
  /// distinct from [productNameSnapshot], which is frozen at scan time from
  /// product data.
  TextColumn get name => text().nullable()();

  /// Free text. History groups scans that share the same value (§7.4,
  /// R7.12). Purely a label the user typed — no shops table, no
  /// normalisation.
  TextColumn get shop => text().nullable()();

  /// Relative path under the app documents dir to a user-attached photo
  /// (`ScanPhotoService`), e.g. `scan_photos/<id>.jpg`. Set only via "Edit
  /// details", never at scan time — unrelated to the OCR capture photo,
  /// which is never persisted (N10 / N10a).
  TextColumn get photoPath => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
