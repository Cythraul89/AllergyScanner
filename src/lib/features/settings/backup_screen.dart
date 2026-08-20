import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/backup_service.dart';
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

    return Scaffold(
      appBar: AppBar(title: const Text('Local backup')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text('Export', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'Writes your allergy terms, products, history and settings into a '
            'ZIP archive. Passwords are never included.',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _export,
            icon: const Icon(Icons.upload_file_outlined),
            label: const Text('Export archive'),
          ),
          const SizedBox(height: 32),

          Text('Import', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'Reads an archive back. Rows that cannot be attached — for example '
            'a match whose scan is missing — are skipped and counted.',
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _import,
            icon: const Icon(Icons.download_outlined),
            label: const Text('Import archive'),
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

  Future<void> _export() async {
    setState(() {
      _busy = true;
      _status = null;
    });

    try {
      final File archive = await ref.read(backupActionsProvider).exportArchive();
      _report('Exported to ${archive.path}');
    } on Object catch (cause) {
      _report('Export failed: $cause');
    }
  }

  Future<void> _import() async {
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
            ? 'Imported ${outcome.imported} rows, skipped ${outcome.skipped}.'
            : 'Imported ${outcome.imported} rows.',
      );
    } on BackupFormatException catch (exception) {
      _report(exception.message);
    } on Object catch (cause) {
      _report('Import failed: $cause');
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
