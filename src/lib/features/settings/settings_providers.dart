import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/database/daos/settings_dao.dart';
import '../../core/models/app_settings.dart';
import '../../core/providers.dart';
import '../../core/services/backup_service.dart';
import '../../core/services/log_service.dart';
import '../../core/services/webdav_service.dart';

final Provider<BackupActions> backupActionsProvider = Provider<BackupActions>((
  ref,
) {
  return BackupActions(
    backup: ref.watch(backupServiceProvider),
    webdav: ref.watch(webdavServiceProvider),
    settingsDao: ref.watch(settingsDaoProvider),
    secureStorage: ref.watch(secureStorageProvider),
    log: ref.watch(logServiceProvider),
  );
});

/// Backup, import and the optional WebDAV sync.
///
/// The password is the only value that goes to the platform key store, and it
/// never reaches the database, a log line or the archive (R4.9).
class BackupActions {
  BackupActions({
    required BackupService backup,
    required WebdavService webdav,
    required SettingsDao settingsDao,
    required FlutterSecureStorage secureStorage,
    required LogService log,
    DateTime Function()? now,
  }) : _backup = backup,
       _webdav = webdav,
       _settingsDao = settingsDao,
       _secureStorage = secureStorage,
       _log = log,
       _now = now ?? DateTime.now;

  static const String _passwordKey = 'webdav_password';

  final BackupService _backup;
  final WebdavService _webdav;
  final SettingsDao _settingsDao;
  final FlutterSecureStorage _secureStorage;
  final LogService _log;
  final DateTime Function() _now;

  Future<File> exportArchive() => _backup.exportToFile();

  Future<ImportOutcome> importArchive(File file) =>
      _backup.importFromFile(file);

  Future<String?> loadPassword() => _secureStorage.read(key: _passwordKey);

  Future<void> saveConnection({
    required String baseUrl,
    required String username,
    required String password,
  }) async {
    await _secureStorage.write(key: _passwordKey, value: password);
    await _settingsDao.setWebdav(baseUrl: baseUrl, username: username);
  }

  Future<void> clearConnection() async {
    await _secureStorage.delete(key: _passwordKey);
    await _settingsDao.setWebdav();
    await _settingsDao.setLastSyncAt(null);
  }

  Future<void> pinCertificate(String fingerprint) async {
    final AppSettings settings = await _settingsDao.get();
    await _settingsDao.setWebdav(
      baseUrl: settings.webdavBaseUrl,
      username: settings.webdavUsername,
      certificateFingerprint: fingerprint,
    );
  }

  /// `null` when sync is not configured — every caller must handle that rather
  /// than assume a server exists.
  Future<WebdavCredentials?> buildCredentials() async {
    final AppSettings settings = await _settingsDao.get();
    final String? password = await loadPassword();
    if (!settings.isSyncConfigured || password == null) return null;

    return WebdavCredentials(
      baseUrl: settings.webdavBaseUrl!,
      username: settings.webdavUsername!,
      password: password,
      certificateFingerprint: settings.certificateFingerprint,
    );
  }

  Future<WebdavOutcome> testConnection(WebdavCredentials credentials) =>
      _webdav.testConnection(credentials);

  Future<WebdavOutcome> uploadNow() async {
    final WebdavCredentials? credentials = await buildCredentials();
    if (credentials == null) {
      return const WebdavFailure('Sync is not configured.');
    }

    final File archive = await exportArchive();
    final WebdavOutcome outcome = await _webdav.uploadBackup(
      credentials,
      archive,
    );
    if (outcome is WebdavSuccess) {
      await _settingsDao.setLastSyncAt(_now());
    }
    return outcome;
  }

  /// Downloads the newest remote archive and imports it.
  Future<WebdavOutcome> restoreLatest() async {
    final WebdavCredentials? credentials = await buildCredentials();
    if (credentials == null) {
      return const WebdavFailure('Sync is not configured.');
    }

    final WebdavOutcome lookup = await _webdav.findLatestBackupName(
      credentials,
    );
    if (lookup is! WebdavSuccess<String>) return lookup;

    final String? name = lookup.value;
    if (name == null) {
      return const WebdavFailure('No backup was found on the server.');
    }

    final WebdavOutcome download = await _webdav.downloadBackup(
      credentials,
      name,
    );
    if (download is! WebdavSuccess<List<int>>) return download;

    final List<int>? bytes = download.value;
    if (bytes == null) {
      return const WebdavFailure('The downloaded archive was empty.');
    }

    try {
      final ImportOutcome result = await _backup.importFromBytes(bytes);
      await _settingsDao.setLastSyncAt(_now());
      _log.info('Restored $name: ${result.imported} rows');
      return WebdavSuccess<ImportOutcome>(result);
    } on BackupFormatException catch (exception) {
      return WebdavFailure(
        'The backup on the server could not be restored '
        '(${exception.problem.runtimeType}).',
      );
    }
  }
}
