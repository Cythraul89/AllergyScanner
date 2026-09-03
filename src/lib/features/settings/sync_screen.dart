import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/app_settings.dart';
import '../../core/providers.dart';
import '../../core/services/backup_service.dart';
import '../../core/services/webdav_service.dart';
import '../../core/utils/formatters.dart';
import '../../l10n/app_localizations.dart';
import 'settings_providers.dart';

/// Optional Nextcloud/WebDAV sync of the backup archive.
///
/// Flow: test connection → offer to pin an untrusted certificate → save →
/// upload or restore on demand (R8.4). Nothing here is scheduled; the app has
/// no background work.
class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key});

  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _loading = true;
  bool _busy = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _userController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final AppSettings settings = await ref.read(settingsDaoProvider).get();
    final String? password = await ref
        .read(backupActionsProvider)
        .loadPassword();
    if (!mounted) return;
    setState(() {
      _urlController.text = settings.webdavBaseUrl ?? '';
      _userController.text = settings.webdavUsername ?? '';
      _passwordController.text = password ?? '';
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppSettings settings = ref.watch(currentSettingsProvider);
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsSyncTitle)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                Text(l10n.syncIntro),
                const SizedBox(height: 16),
                TextField(
                  controller: _urlController,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    labelText: l10n.syncUrlLabel,
                    hintText:
                        'https://cloud.example.org/remote.php/dav/files/me/allergy/',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _userController,
                  decoration: InputDecoration(
                    labelText: l10n.syncUsernameLabel,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: l10n.syncPasswordLabel,
                    border: const OutlineInputBorder(),
                    helperText: l10n.syncPasswordHelper,
                  ),
                ),
                const SizedBox(height: 16),
                if (settings.certificateFingerprint != null)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.lock_outline),
                      title: Text(l10n.syncPinnedCertTitle),
                      subtitle: Text(
                        settings.certificateFingerprint!,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: <Widget>[
                    FilledButton(
                      onPressed: _busy ? null : () => _testAndSave(l10n),
                      child: Text(l10n.syncTestAndSaveAction),
                    ),
                    OutlinedButton(
                      onPressed: _busy || !settings.isSyncConfigured
                          ? null
                          : () => _upload(l10n),
                      child: Text(l10n.syncUploadNowAction),
                    ),
                    OutlinedButton(
                      onPressed: _busy || !settings.isSyncConfigured
                          ? null
                          : () => _restore(l10n),
                      child: Text(l10n.syncRestoreAction),
                    ),
                    if (settings.isSyncConfigured)
                      TextButton(
                        onPressed: _busy ? null : () => _clear(l10n),
                        child: Text(l10n.syncRemoveConnectionAction),
                      ),
                  ],
                ),
                if (settings.lastSyncAt != null) ...<Widget>[
                  const SizedBox(height: 16),
                  Text(
                    l10n.settingsSyncLastSync(
                      Formatters.dateTime(settings.lastSyncAt!),
                    ),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                if (_busy) ...<Widget>[
                  const SizedBox(height: 24),
                  const Center(child: CircularProgressIndicator()),
                ],
                if (_status != null) ...<Widget>[
                  const SizedBox(height: 24),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(_status!),
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Future<void> _testAndSave(AppLocalizations l10n) async {
    final String baseUrl = _urlController.text.trim();
    final String username = _userController.text.trim();
    final String password = _passwordController.text;
    if (baseUrl.isEmpty || username.isEmpty || password.isEmpty) {
      _report(l10n.syncFillFieldsFirst);
      return;
    }

    setState(() {
      _busy = true;
      _status = null;
    });

    final AppSettings settings = await ref.read(settingsDaoProvider).get();
    final WebdavOutcome outcome = await ref
        .read(backupActionsProvider)
        .testConnection(
          WebdavCredentials(
            baseUrl: baseUrl,
            username: username,
            password: password,
            certificateFingerprint: settings.certificateFingerprint,
          ),
        );

    if (!mounted) return;

    switch (outcome) {
      case WebdavSuccess():
        await ref.read(backupActionsProvider).saveConnection(
          baseUrl: baseUrl,
          username: username,
          password: password,
        );
        _report(l10n.syncConnectionSaved);
      case WebdavUntrustedCertificate(
        observedFingerprint: final String fingerprint,
      ):
        setState(() => _busy = false);
        await _offerPinning(fingerprint, l10n);
      case WebdavAuthenticationFailed():
        _report(l10n.syncAuthRejected);
      case WebdavTransient():
        _report(l10n.syncServerUnreachable);
      // WebdavFailure carries whatever text webdav_service.dart produced,
      // sometimes a raw exception message — left as-is rather than
      // half-translated (doc/ARCHITECTURE.md's i18n boundary note).
      case WebdavFailure(message: final String message):
        _report(message);
    }
  }

  /// A self-signed certificate is accepted only after the user has seen its
  /// fingerprint; a later mismatch then rejects the connection.
  Future<void> _offerPinning(String fingerprint, AppLocalizations l10n) async {
    final bool? trust = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(l10n.syncUntrustedCertTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(l10n.syncUntrustedCertMessage),
            const SizedBox(height: 12),
            SelectableText(
              fingerprint,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.syncTrustCertAction),
          ),
        ],
      ),
    );

    if (trust ?? false) {
      await ref.read(backupActionsProvider).pinCertificate(fingerprint);
      if (!mounted) return;
      _report(l10n.syncCertPinned);
    }
  }

  Future<void> _upload(AppLocalizations l10n) async {
    setState(() {
      _busy = true;
      _status = null;
    });
    final WebdavOutcome outcome = await ref
        .read(backupActionsProvider)
        .uploadNow();
    _report(_describe(l10n, outcome, success: l10n.syncUploadSuccess));
  }

  Future<void> _restore(AppLocalizations l10n) async {
    setState(() {
      _busy = true;
      _status = null;
    });
    final WebdavOutcome outcome = await ref
        .read(backupActionsProvider)
        .restoreLatest();

    if (outcome is WebdavSuccess<ImportOutcome>) {
      final ImportOutcome? result = outcome.value;
      _report(
        result == null
            ? l10n.syncRestoredNoDetail
            : result.hasSkipped
            ? l10n.syncRestoredWithSkipped(result.imported, result.skipped)
            : l10n.syncRestoredCount(result.imported),
      );
      return;
    }
    _report(_describe(l10n, outcome, success: l10n.syncRestoredNoDetail));
  }

  Future<void> _clear(AppLocalizations l10n) async {
    await ref.read(backupActionsProvider).clearConnection();
    if (!mounted) return;
    _passwordController.clear();
    _report(l10n.syncConnectionRemoved);
  }

  static String _describe(
    AppLocalizations l10n,
    WebdavOutcome outcome, {
    required String success,
  }) {
    switch (outcome) {
      case WebdavSuccess():
        return success;
      case WebdavUntrustedCertificate():
        return l10n.syncCertNotTrusted;
      case WebdavAuthenticationFailed():
        return l10n.syncStoredCredsRejected;
      case WebdavTransient():
        return l10n.syncServerUnreachable;
      case WebdavFailure(message: final String message):
        return message;
    }
  }

  void _report(String message) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = message;
    });
  }
}
