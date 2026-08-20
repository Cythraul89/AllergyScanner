import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart' show ThemeMode;

/// The single settings row (id = 1), or the defaults while it does not exist.
class AppSettings extends Equatable {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.preferredIngredientsLanguage = 'en',
    this.remoteLookupEnabled = true,
    this.disclaimerAcknowledgedAt,
    this.webdavBaseUrl,
    this.webdavUsername,
    this.certificateFingerprint,
    this.lastSyncAt,
  });

  final ThemeMode themeMode;
  final String preferredIngredientsLanguage;
  final bool remoteLookupEnabled;
  final DateTime? disclaimerAcknowledgedAt;
  final String? webdavBaseUrl;
  final String? webdavUsername;
  final String? certificateFingerprint;
  final DateTime? lastSyncAt;

  bool get disclaimerAcknowledged => disclaimerAcknowledgedAt != null;

  bool get isSyncConfigured =>
      (webdavBaseUrl ?? '').isNotEmpty && (webdavUsername ?? '').isNotEmpty;

  @override
  List<Object?> get props => [
    themeMode,
    preferredIngredientsLanguage,
    remoteLookupEnabled,
    disclaimerAcknowledgedAt,
    webdavBaseUrl,
    webdavUsername,
    certificateFingerprint,
    lastSyncAt,
  ];
}
