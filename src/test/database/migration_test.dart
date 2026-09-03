import 'dart:io';

import 'package:allergy_scanner/core/database/app_database.dart';
import 'package:allergy_scanner/core/models/scan.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path_helper;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// The app's first real schema migration (v1 -> v2): a new `allergen_groups`
/// table plus nullable columns on `allergen_terms` and `scans`. This test
/// hand-builds a minimal, representative v1 database with raw SQL — rather
/// than drift_dev's schema-snapshot tooling, which needs a build.yaml
/// scaffold this project doesn't have yet — and opens it through the real
/// `AppDatabase`/`MigrationStrategy.onUpgrade`, so what's exercised is this
/// project's actual migration code, not a hand-simulation of it. Column
/// naming/types (snake_case, DateTime as unix-epoch-seconds INTEGER, bool as
/// 0/1 INTEGER) were confirmed empirically against this project's real
/// Drift/sqlite3 versions, not assumed. Deliberately narrow: only the tables
/// touched by a migration between v1 and the current `schemaVersion` are
/// recreated at their pre-migration shape (settings_entries is included here
/// purely so the v1<3 `appLanguage` step below has a table to alter — a v1
/// install always had it, the seed just wouldn't otherwise, since there is
/// only one live `AppDatabase.schemaVersion` and `onUpgrade` runs every
/// `if (from < N)` block in one hop); `barcode` is a plain nullable column
/// here (no FK to a `products` table), since testing that FK is not this
/// migration's concern.
void main() {
  late String path;

  setUp(() {
    path = path_helper.join(
      Directory.systemTemp.path,
      'allergy_scanner_migration_test.sqlite',
    );
    if (File(path).existsSync()) File(path).deleteSync();
  });

  tearDown(() {
    if (File(path).existsSync()) File(path).deleteSync();
  });

  test('a v1 database upgrades to v2 without losing existing rows', () async {
    final sqlite3.Database seed = sqlite3.sqlite3.open(path);
    seed.execute('''
      CREATE TABLE allergen_terms (
        id TEXT NOT NULL PRIMARY KEY,
        term TEXT NOT NULL,
        normalized_term TEXT NOT NULL UNIQUE,
        is_active INTEGER NOT NULL DEFAULT 1,
        note TEXT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
      CREATE TABLE scans (
        id TEXT NOT NULL PRIMARY KEY,
        scanned_at INTEGER NOT NULL,
        input_mode INTEGER NOT NULL,
        barcode TEXT NULL,
        product_name_snapshot TEXT NULL,
        evaluated_text TEXT NOT NULL,
        verdict INTEGER NOT NULL,
        match_count INTEGER NOT NULL DEFAULT 0
      );
      CREATE TABLE settings_entries (
        id INTEGER NOT NULL PRIMARY KEY,
        theme_mode INTEGER NOT NULL DEFAULT 0,
        preferred_ingredients_language TEXT NOT NULL DEFAULT 'en',
        remote_lookup_enabled INTEGER NOT NULL DEFAULT 1,
        disclaimer_acknowledged_at INTEGER NULL,
        webdav_base_url TEXT NULL,
        webdav_username TEXT NULL,
        certificate_fingerprint TEXT NULL,
        last_sync_at INTEGER NULL
      );
    ''');
    final int ts = DateTime.utc(2026, 1, 2, 3, 4, 5).millisecondsSinceEpoch ~/ 1000;
    seed.execute(
      'INSERT INTO allergen_terms '
      '(id, term, normalized_term, is_active, note, created_at, updated_at) '
      "VALUES ('term-1', 'Hazelnut', 'hazelnut', 1, NULL, $ts, $ts)",
    );
    seed.execute(
      'INSERT INTO scans '
      '(id, scanned_at, input_mode, barcode, product_name_snapshot, '
      'evaluated_text, verdict, match_count) '
      "VALUES ('scan-1', $ts, 0, NULL, NULL, 'sugar, hazelnuts', 1, 1)",
    );
    seed.execute('PRAGMA user_version = 1');
    seed.close();

    final AppDatabase database = AppDatabase.forTesting(
      NativeDatabase(File(path)),
    );
    addTearDown(database.close);

    final term = await database.allergenTermDao.findById('term-1');
    expect(term, isNotNull);
    expect(term!.term, 'Hazelnut');
    expect(term.groupId, isNull);

    final List<Scan> scans = await database.scanDao.getAll();
    expect(scans, hasLength(1));
    final Scan scan = scans.single;
    expect(scan.evaluatedText, 'sugar, hazelnuts');
    expect(scan.name, isNull);
    expect(scan.shop, isNull);
    expect(scan.photoPath, isNull);

    // allergen_groups exists and is usable through the real generated API.
    final DateTime now = DateTime.utc(2026, 1, 2);
    await database
        .into(database.allergenGroups)
        .insert(
          AllergenGroupsCompanion.insert(
            id: 'group-1',
            label: 'Hazelnut',
            createdAt: now,
            updatedAt: now,
          ),
        );
    final List<AllergenGroupRow> groups = await database
        .select(database.allergenGroups)
        .get();
    expect(groups, hasLength(1));
    expect(groups.single.label, 'Hazelnut');
  });

  test(
    'a v2 database upgrades to v3 with appLanguage defaulting to null',
    () async {
      final sqlite3.Database seed = sqlite3.sqlite3.open(path);
      seed.execute('''
      CREATE TABLE settings_entries (
        id INTEGER NOT NULL PRIMARY KEY,
        theme_mode INTEGER NOT NULL DEFAULT 0,
        preferred_ingredients_language TEXT NOT NULL DEFAULT 'en',
        remote_lookup_enabled INTEGER NOT NULL DEFAULT 1,
        disclaimer_acknowledged_at INTEGER NULL,
        webdav_base_url TEXT NULL,
        webdav_username TEXT NULL,
        certificate_fingerprint TEXT NULL,
        last_sync_at INTEGER NULL
      );
    ''');
      seed.execute(
        'INSERT INTO settings_entries '
        '(id, theme_mode, preferred_ingredients_language, remote_lookup_enabled) '
        "VALUES (1, 1, 'de', 1)",
      );
      seed.execute('PRAGMA user_version = 2');
      seed.close();

      final AppDatabase database = AppDatabase.forTesting(
        NativeDatabase(File(path)),
      );
      addTearDown(database.close);

      final settings = await database.settingsDao.get();
      expect(settings.themeMode.index, 1);
      expect(settings.preferredIngredientsLanguage, 'de');
      expect(settings.appLanguage, isNull);
    },
  );
}
