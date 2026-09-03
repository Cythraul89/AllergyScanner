import 'package:drift/drift.dart';
import 'package:flutter/material.dart' show ThemeMode;

import '../../models/app_settings.dart';
import '../app_database.dart';
import '../tables/settings_table.dart';

part 'settings_dao.g.dart';

@DriftAccessor(tables: [SettingsEntries])
class SettingsDao extends DatabaseAccessor<AppDatabase>
    with _$SettingsDaoMixin {
  SettingsDao(super.attachedDatabase);

  static const int _rowId = 1;

  /// Reads never write. While the row does not exist the defaults are served,
  /// and the first setter creates it.
  Stream<AppSettings> watch() {
    return (select(settingsEntries)..where((t) => t.id.equals(_rowId)))
        .watchSingleOrNull()
        .map((row) => row == null ? const AppSettings() : _toModel(row));
  }

  Future<AppSettings> get() async {
    final row = await (select(
      settingsEntries,
    )..where((t) => t.id.equals(_rowId))).getSingleOrNull();
    return row == null ? const AppSettings() : _toModel(row);
  }

  /// Called once at startup so the ingredient language starts at the device
  /// locale instead of the hardcoded fallback. Existing rows are untouched.
  Future<void> ensureDefaults({required String deviceLanguage}) {
    return into(settingsEntries).insert(
      SettingsEntriesCompanion.insert(
        id: const Value(_rowId),
        preferredIngredientsLanguage: Value(deviceLanguage),
      ),
      mode: InsertMode.insertOrIgnore,
    );
  }

  Future<void> setThemeMode(ThemeMode mode) =>
      _write(SettingsEntriesCompanion(themeMode: Value(mode)));

  /// `null` reverts to following the system language.
  Future<void> setAppLanguage(String? language) =>
      _write(SettingsEntriesCompanion(appLanguage: Value(language)));

  Future<void> setRemoteLookupEnabled(bool enabled) =>
      _write(SettingsEntriesCompanion(remoteLookupEnabled: Value(enabled)));

  Future<void> setPreferredLanguage(String language) => _write(
    SettingsEntriesCompanion(preferredIngredientsLanguage: Value(language)),
  );

  Future<void> acknowledgeDisclaimer(DateTime at) =>
      _write(SettingsEntriesCompanion(disclaimerAcknowledgedAt: Value(at)));

  Future<void> setWebdav({
    String? baseUrl,
    String? username,
    String? certificateFingerprint,
  }) {
    return _write(
      SettingsEntriesCompanion(
        webdavBaseUrl: Value(baseUrl),
        webdavUsername: Value(username),
        certificateFingerprint: Value(certificateFingerprint),
      ),
    );
  }

  Future<void> setLastSyncAt(DateTime? at) =>
      _write(SettingsEntriesCompanion(lastSyncAt: Value(at)));

  /// Column-scoped write: creates the row if needed, then updates only the
  /// fields present in [changes]. Never writes back a whole cached snapshot.
  Future<void> _write(SettingsEntriesCompanion changes) {
    return transaction(() async {
      await into(settingsEntries).insert(
        const SettingsEntriesCompanion(id: Value(_rowId)),
        mode: InsertMode.insertOrIgnore,
      );
      await (update(
        settingsEntries,
      )..where((t) => t.id.equals(_rowId))).write(changes);
    });
  }

  static AppSettings _toModel(SettingsRow row) {
    return AppSettings(
      themeMode: row.themeMode,
      appLanguage: row.appLanguage,
      preferredIngredientsLanguage: row.preferredIngredientsLanguage,
      remoteLookupEnabled: row.remoteLookupEnabled,
      disclaimerAcknowledgedAt: row.disclaimerAcknowledgedAt,
      webdavBaseUrl: row.webdavBaseUrl,
      webdavUsername: row.webdavUsername,
      certificateFingerprint: row.certificateFingerprint,
      lastSyncAt: row.lastSyncAt,
    );
  }
}
