import 'package:drift/drift.dart';
import 'package:flutter/material.dart' show ThemeMode;

/// Single-row settings table, always `id = 1` (REQUIREMENTS §4.5).
///
/// The WebDAV password is deliberately absent — it lives in
/// `flutter_secure_storage` and never in the database, a log or a backup.
@DataClassName('SettingsRow')
class SettingsEntries extends Table {
  IntColumn get id => integer()();

  IntColumn get themeMode =>
      intEnum<ThemeMode>().withDefault(const Constant(0))();

  /// `null` follows the system language; `'en'`/`'de'` overrides it
  /// (REQUIREMENTS R7.15). Unlike [preferredIngredientsLanguage], there is no
  /// concrete fallback to fill in — "follow the system" is a real, permanent
  /// state, not just an unset default.
  TextColumn get appLanguage => text().nullable()();

  TextColumn get preferredIngredientsLanguage =>
      text().withDefault(const Constant('en'))();

  /// `false` disables every HTTP request to Open Food Facts (R6.6).
  BoolColumn get remoteLookupEnabled =>
      boolean().withDefault(const Constant(true))();

  DateTimeColumn get disclaimerAcknowledgedAt => dateTime().nullable()();

  TextColumn get webdavBaseUrl => text().nullable()();
  TextColumn get webdavUsername => text().nullable()();

  /// SHA-256 fingerprint for pinning a self-signed WebDAV certificate.
  TextColumn get certificateFingerprint => text().nullable()();

  DateTimeColumn get lastSyncAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
