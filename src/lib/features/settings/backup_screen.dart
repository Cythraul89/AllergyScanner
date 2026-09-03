import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/backup_service.dart';
import '../../l10n/app_localizations.dart';
import 'settings_providers.dart';

/// Local ZIP export and import — the fallback that always exists, with or
/// without a configured server.
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _busy = false;
  String? _status;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.backupTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(l10n.backupExportHeading, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(l10n.backupExportNote),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : () => _export(l10n),
            icon: const Icon(Icons.upload_file_outlined),
            label: Text(l10n.backupExportAction),
          ),
          const SizedBox(height: 32),

          Text(l10n.backupImportHeading, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(l10n.backupImportNote),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _import(l10n),
            icon: const Icon(Icons.download_outlined),
            label: Text(l10n.backupImportAction),
          ),

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

  Future<void> _export(AppLocalizations l10n) async {
    setState(() {
      _busy = true;
      _status = null;
    });

    try {
      final File archive = await ref.read(backupActionsProvider).exportArchive();
      _report(l10n.backupExportedTo(archive.path));
    } on Object catch (cause) {
      _report(l10n.backupExportFailed(cause.toString()));
    }
  }

  Future<void> _import(AppLocalizations l10n) async {
    final PlatformFile? picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: <String>['zip'],
    );
    final String? path = picked?.path;
    if (path == null) return;

    setState(() {
      _busy = true;
      _status = null;
    });

    try {
      final ImportOutcome outcome = await ref
          .read(backupActionsProvider)
          .importArchive(File(path));
      // A skip count above zero must be surfaced, not swallowed (R8.2).
      _report(
        outcome.hasSkipped
            ? l10n.backupImportedWithSkipped(outcome.imported, outcome.skipped)
            : l10n.backupImportedCount(outcome.imported),
      );
    } on BackupFormatException catch (exception) {
      _report(_describeProblem(l10n, exception.problem));
    } on Object catch (cause) {
      _report(l10n.backupImportFailed(cause.toString()));
    }
  }

  static String _describeProblem(
    AppLocalizations l10n,
    BackupFormatProblem problem,
  ) {
    switch (problem) {
      case ArchiveUnreadable():
        return l10n.backupProblemUnreadable;
      case ArchiveMissingData():
        return l10n.backupProblemMissingData;
      case ArchiveContentInvalid():
        return l10n.backupProblemContentInvalid;
      case ArchiveSchemaTooNew(
        archiveSchemaVersion: final int archive,
        appSchemaVersion: final int app,
      ):
        return l10n.backupProblemSchemaTooNew(archive, app);
      case ArchiveFormatTooNew(
        archiveFormatVersion: final int archive,
        appFormatVersion: final int app,
      ):
        return l10n.backupProblemFormatTooNew(archive, app);
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
