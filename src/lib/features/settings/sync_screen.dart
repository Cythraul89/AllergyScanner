import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/app_settings.dart';
import '../../core/providers.dart';
import '../../core/services/backup_service.dart';
import '../../core/services/webdav_service.dart';
import '../../core/utils/formatters.dart';
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

    return Scaffold(
      appBar: AppBar(title: const Text('Nextcloud sync')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                const Text(
                  'Uploads and downloads the same ZIP archive as the local '
                  'backup, to a folder on your own server. Everything works '
                  'without this.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _urlController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'WebDAV folder URL',
                    hintText:
                        'https://cloud.example.org/remote.php/dav/files/me/allergy/',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _userController,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'App password',
                    border: OutlineInputBorder(),
                    helperText: 'Stored in the platform key store only',
                  ),
                ),
                const SizedBox(height: 16),
                if (settings.certificateFingerprint != null)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.lock_outline),
                      title: const Text('Pinned certificate'),
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
                      onPressed: _busy ? null : _testAndSave,
                      child: const Text('Test and save'),
                    ),
                    OutlinedButton(
                      onPressed: _busy || !settings.isSyncConfigured
                          ? null
                          : _upload,
                      child: const Text('Upload now'),
                    ),
                    OutlinedButton(
                      onPressed: _busy || !settings.isSyncConfigured
                          ? null
                          : _restore,
                      child: const Text('Restore from server'),
                    ),
                    if (settings.isSyncConfigured)
                      TextButton(
                        onPressed: _busy ? null : _clear,
                        child: const Text('Remove connection'),
                      ),
                  ],
                ),
                if (settings.lastSyncAt != null) ...<Widget>[
                  const SizedBox(height: 16),
                  Text(
                    'Last sync ${Formatters.dateTime(settings.lastSyncAt!)}',
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

  Future<void> _testAndSave() async {
    final String baseUrl = _urlController.text.trim();
    final String username = _userController.text.trim();
    final String password = _passwordController.text;
    if (baseUrl.isEmpty || username.isEmpty || password.isEmpty) {
      _report('Fill in URL, username and password first.');
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
        _report('Connection works. Saved.');
      case WebdavUntrustedCertificate(
        observedFingerprint: final String fingerprint,
      ):
        setState(() => _busy = false);
        await _offerPinning(fingerprint);
      case WebdavAuthenticationFailed():
        _report('The server rejected these credentials.');
      case WebdavTransient():
        _report('The server could not be reached. A retry may help.');
      case WebdavFailure(message: final String message):
        _report(message);
    }
  }

  /// A self-signed certificate is accepted only after the user has seen its
  /// fingerprint; a later mismatch then rejects the connection.
  Future<void> _offerPinning(String fingerprint) async {
    final bool? trust = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Untrusted certificate'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'The server presented a certificate that your device does not '
              'trust. Compare its fingerprint with your server before you '
              'accept it.',
            ),
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
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Trust this certificate'),
          ),
        ],
      ),
    );

    if (trust ?? false) {
      await ref.read(backupActionsProvider).pinCertificate(fingerprint);
      if (!mounted) return;
      _report('Certificate pinned. Test and save again.');
    }
  }

  Future<void> _upload() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    final WebdavOutcome outcome = await ref
        .read(backupActionsProvider)
        .uploadNow();
    _report(_describe(outcome, success: 'Backup uploaded.'));
  }

  Future<void> _restore() async {
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
            ? 'Restored.'
            : result.hasSkipped
            ? 'Restored ${result.imported} rows, skipped ${result.skipped}.'
            : 'Restored ${result.imported} rows.',
      );
      return;
    }
    _report(_describe(outcome, success: 'Restored.'));
  }

  Future<void> _clear() async {
    await ref.read(backupActionsProvider).clearConnection();
    if (!mounted) return;
    _passwordController.clear();
    _report('Connection removed. The stored password was deleted.');
  }

  static String _describe(WebdavOutcome outcome, {required String success}) {
    switch (outcome) {
      case WebdavSuccess():
        return success;
      case WebdavUntrustedCertificate():
        return 'The server certificate is not trusted.';
      case WebdavAuthenticationFailed():
        return 'The server rejected the stored credentials.';
      case WebdavTransient():
        return 'The server could not be reached. A retry may help.';
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
