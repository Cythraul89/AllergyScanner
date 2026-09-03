import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/providers.dart';
import '../../core/services/log_service.dart';
import '../../l10n/app_localizations.dart';

/// The app log, so a user can report a problem without a debugger attached.
class LogsScreen extends ConsumerStatefulWidget {
  const LogsScreen({super.key});

  @override
  ConsumerState<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends ConsumerState<LogsScreen> {
  String _content = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final LogService log = ref.read(logServiceProvider);
    await log.flush();
    final String content = await log.read();
    if (!mounted) return;
    setState(() {
      _content = content;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsLogsTitle),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l10n.logsReloadTooltip,
            onPressed: _reload,
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: l10n.logsShareTooltip,
            onPressed: _content.isEmpty ? null : _share,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: l10n.historyClearConfirm,
            onPressed: _clear,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _content.isEmpty
          ? Center(child: Text(l10n.logsEmptyMessage))
          : Scrollbar(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  _content,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
    );
  }

  /// Shared as text rather than as a file: the log is small, and this keeps the
  /// file out of any share target's storage.
  Future<void> _share() =>
      SharePlus.instance.share(ShareParams(text: _content));

  Future<void> _clear() async {
    await ref.read(logServiceProvider).clear();
    await _reload();
  }
}
