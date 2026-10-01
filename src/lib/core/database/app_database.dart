import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/material.dart' show ThemeMode;

import '../models/enums.dart';
import 'daos/allergen_group_dao.dart';
import 'daos/allergen_term_dao.dart';
import 'daos/product_dao.dart';
import 'daos/scan_dao.dart';
import 'daos/settings_dao.dart';
import 'tables/allergen_groups_table.dart';
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
  tables: [
    AllergenTerms,
    AllergenGroups,
    Products,
    Scans,
    ScanMatches,
    SettingsEntries,
  ],
  daos: [AllergenTermDao, AllergenGroupDao, ProductDao, ScanDao, SettingsDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'allergy_scanner'));

  /// In-memory database for tests: `AppDatabase.forTesting(NativeDatabase.memory())`.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator migrator) async {
      await migrator.createAll();
    },
    onUpgrade: (Migrator migrator, int from, int to) async {
      // Drift calls onUpgrade for a *downgrade* too, where every `if (from <
      // N)` below is false — it would silently do nothing and then stamp the
      // older schemaVersion onto a newer database. Re-installing the newer
      // build would then re-run the addColumn steps against columns that
      // already exist ("duplicate column"), and the database would never open
      // again. Fail here instead, while the data is still intact.
      if (from > to) {
        throw StateError(
          'Cannot open a database created by a newer version of the app '
          '(database schema v$from, this build expects v$to). Install the '
          'newer version again, or restore from a backup.',
        );
      }
      if (from < 2) {
        // Allergen groups: an organisational layer over existing terms,
        // added nullable so every pre-existing term simply starts ungrouped.
        await migrator.createTable(allergenGroups);
        await migrator.addColumn(allergenTerms, allergenTerms.groupId);
        // History details, added after the fact via "Edit details" — never
        // touch evaluatedText/verdict, so R4.7's snapshot guarantee holds.
        await migrator.addColumn(scans, scans.name);
        await migrator.addColumn(scans, scans.shop);
        await migrator.addColumn(scans, scans.photoPath);
      }
      if (from < 3) {
        // App UI language override; null (follow system) for every existing
        // row, exactly today's behaviour.
        await migrator.addColumn(settingsEntries, settingsEntries.appLanguage);
      }
      if (from >= 2 && from < 4) {
        // Optional visual color + severity tag on a group, added after the
        // fact — null for every existing group, exactly today's behaviour.
        //
        // Guarded by `from >= 2`: `Migrator.createTable` always builds a
        // table from its *current* Dart definition, not a per-version
        // snapshot (this project hand-writes migrations rather than using
        // drift_dev's schema-snapshot tooling — see migration_test.dart's own
        // doc comment). So the `from < 2` block above already creates
        // `allergenGroups` with these two columns included; adding them
        // again here for a from-v1 upgrade fails with "duplicate column".
        // Confirmed empirically via the migration tests, not assumed.
        await migrator.addColumn(allergenGroups, allergenGroups.color);
        await migrator.addColumn(allergenGroups, allergenGroups.criticality);
      }
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
