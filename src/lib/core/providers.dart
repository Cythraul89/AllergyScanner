import 'package:dio/dio.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'database/app_database.dart';
import 'database/daos/allergen_group_dao.dart';
import 'database/daos/allergen_term_dao.dart';
import 'database/daos/product_dao.dart';
import 'database/daos/scan_dao.dart';
import 'database/daos/settings_dao.dart';
import 'models/allergen_term.dart';
import 'models/app_settings.dart';
import 'services/backup_service.dart';
import 'services/log_service.dart';
import 'services/open_food_facts_service.dart';
import 'services/scan_photo_service.dart';
import 'services/text_recognition_service.dart';
import 'services/translation_service.dart';
import 'services/webdav_service.dart';
import 'utils/app_version.dart';
import 'utils/scan_capabilities.dart';

/// Providers for everything constructed in `main.dart`.
///
/// Each one throws until overridden, so a missing override fails loudly instead
/// of quietly opening a socket or a database file in a test.
Never _mustOverride(String name) =>
    throw UnimplementedError('$name must be overridden in ProviderScope');

final Provider<AppDatabase> appDatabaseProvider = Provider<AppDatabase>(
  (ref) => _mustOverride('appDatabaseProvider'),
);

final Provider<LogService> logServiceProvider = Provider<LogService>(
  (ref) => _mustOverride('logServiceProvider'),
);

final Provider<Dio> dioProvider = Provider<Dio>(
  (ref) => _mustOverride('dioProvider'),
);

final Provider<OpenFoodFactsService> openFoodFactsServiceProvider =
    Provider<OpenFoodFactsService>(
      (ref) => _mustOverride('openFoodFactsServiceProvider'),
    );

final Provider<TextRecognitionService> textRecognitionServiceProvider =
    Provider<TextRecognitionService>(
      (ref) => _mustOverride('textRecognitionServiceProvider'),
    );

final Provider<BackupService> backupServiceProvider = Provider<BackupService>(
  (ref) => _mustOverride('backupServiceProvider'),
);

final Provider<WebdavService> webdavServiceProvider = Provider<WebdavService>(
  (ref) => _mustOverride('webdavServiceProvider'),
);

final Provider<TranslationService> translationServiceProvider =
    Provider<TranslationService>(
      (ref) => _mustOverride('translationServiceProvider'),
    );

final Provider<ScanPhotoService> scanPhotoServiceProvider =
    Provider<ScanPhotoService>(
      (ref) => _mustOverride('scanPhotoServiceProvider'),
    );

final Provider<FlutterSecureStorage> secureStorageProvider =
    Provider<FlutterSecureStorage>(
      (ref) => _mustOverride('secureStorageProvider'),
    );

final Provider<AppVersion> appVersionProvider = Provider<AppVersion>(
  (ref) => _mustOverride('appVersionProvider'),
);

/// Platform-derived, so it needs no override outside tests.
final Provider<ScanCapabilities> scanCapabilitiesProvider =
    Provider<ScanCapabilities>(
      (ref) => ScanCapabilities.forCurrentPlatform(),
    );

// ── DAOs ────────────────────────────────────────────────────────────────────

final Provider<AllergenTermDao> allergenTermDaoProvider =
    Provider<AllergenTermDao>(
      (ref) => ref.watch(appDatabaseProvider).allergenTermDao,
    );

final Provider<AllergenGroupDao> allergenGroupDaoProvider =
    Provider<AllergenGroupDao>(
      (ref) => ref.watch(appDatabaseProvider).allergenGroupDao,
    );

final Provider<ProductDao> productDaoProvider = Provider<ProductDao>(
  (ref) => ref.watch(appDatabaseProvider).productDao,
);

final Provider<ScanDao> scanDaoProvider = Provider<ScanDao>(
  (ref) => ref.watch(appDatabaseProvider).scanDao,
);

final Provider<SettingsDao> settingsDaoProvider = Provider<SettingsDao>(
  (ref) => ref.watch(appDatabaseProvider).settingsDao,
);

// ── Allergy terms (read side) ───────────────────────────────────────────────
// Here rather than in a feature: the scan flow, the result view and the
// Allergies screen all read them, and `core/` must not import `features/`.

final StreamProvider<List<AllergenTerm>> allAllergenTermsProvider =
    StreamProvider<List<AllergenTerm>>(
      (ref) => ref.watch(allergenTermDaoProvider).watchAll(),
    );

final StreamProvider<List<AllergenTerm>> activeAllergenTermsProvider =
    StreamProvider<List<AllergenTerm>>(
      (ref) => ref.watch(allergenTermDaoProvider).watchActive(),
    );

// ── Settings (read side) ────────────────────────────────────────────────────

final StreamProvider<AppSettings> settingsProvider =
    StreamProvider<AppSettings>(
      (ref) => ref.watch(settingsDaoProvider).watch(),
    );

/// Defaults while the stream is still loading — the app must render before the
/// first database event arrives.
final Provider<AppSettings> currentSettingsProvider = Provider<AppSettings>(
  (ref) => ref.watch(settingsProvider).value ?? const AppSettings(),
);

final Provider<ThemeMode> themeModeProvider = Provider<ThemeMode>(
  (ref) => ref.watch(currentSettingsProvider).themeMode,
);
