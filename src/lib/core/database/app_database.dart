import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/material.dart' show ThemeMode;

import '../models/enums.dart';
import 'daos/allergen_term_dao.dart';
import 'daos/product_dao.dart';
import 'daos/scan_dao.dart';
import 'daos/settings_dao.dart';
import 'tables/allergen_terms_table.dart';
import 'tables/products_table.dart';
import 'tables/scan_matches_table.dart';
import 'tables/scans_table.dart';
import 'tables/settings_table.dart';

part 'app_database.g.dart';

/// The app's only database.
///
/// `sqlite3_flutter_libs` is end-of-life (0.6.0+eol), so the connection comes
/// from `drift_flutter`'s [driftDatabase], which is drift's current documented
/// setup. It opens on the calling isolate by default — `shareAcrossIsolates` is
/// deliberately not enabled, since nothing here runs in a background isolate.
@DriftDatabase(
  tables: [AllergenTerms, Products, Scans, ScanMatches, SettingsEntries],
  daos: [AllergenTermDao, ProductDao, ScanDao, SettingsDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'allergy_scanner'));

  /// In-memory database for tests: `AppDatabase.forTesting(NativeDatabase.memory())`.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator migrator) async {
      await migrator.createAll();
    },
    onUpgrade: (Migrator migrator, int from, int to) async {
      // schemaVersion is still 1 — no step exists yet. Every future change adds
      // an `if (from < N) { ... }` block here.
      //
      // Reminder: changing TextNormalizer means recomputing
      // allergen_terms.normalized_term for every row in such a block, or
      // matching silently breaks for existing terms.
    },
    beforeOpen: (OpeningDetails details) async {
      // Off by default in SQLite, and this schema relies on cascade/setNull.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
