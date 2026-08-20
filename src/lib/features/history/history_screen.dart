import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/models/enums.dart';
import '../../core/models/scan.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/empty_view.dart';
import '../../core/widgets/error_view.dart';
import '../../core/widgets/verdict_banner.dart';
import 'history_providers.dart';

/// Past checks, newest first, grouped by day. Opening one needs no network:
/// every row is a self-contained snapshot (R4.7).
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Scan>> history = ref.watch(scanHistoryProvider);
    final ScanVerdict? filter = ref.watch(historyFilterProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: <Widget>[
          PopupMenuButton<ScanVerdict?>(
            icon: const Icon(Icons.filter_list),
            tooltip: 'Filter',
            initialValue: filter,
            onSelected: (ScanVerdict? verdict) =>
                ref.read(historyFilterProvider.notifier).state = verdict,
            itemBuilder: (BuildContext context) =>
                <PopupMenuEntry<ScanVerdict?>>[
                  const PopupMenuItem<ScanVerdict?>(child: Text('All')),
                  PopupMenuItem<ScanVerdict?>(
                    value: ScanVerdict.hit,
                    child: Text(Formatters.verdictLabel(ScanVerdict.hit)),
                  ),
                  PopupMenuItem<ScanVerdict?>(
                    value: ScanVerdict.noMatch,
                    child: Text(Formatters.verdictLabel(ScanVerdict.noMatch)),
                  ),
                  PopupMenuItem<ScanVerdict?>(
                    value: ScanVerdict.unknown,
                    child: Text(Formatters.verdictLabel(ScanVerdict.unknown)),
                  ),
                ],
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Clear history',
            onPressed: () => _confirmClear(context, ref),
          ),
        ],
      ),
      body: history.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace _) =>
            ErrorView(message: 'Could not load the history: $error'),
        data: (List<Scan> scans) {
          if (scans.isEmpty) {
            return const EmptyView(
              icon: Icons.history,
              title: 'Nothing checked yet',
              message: 'Every check you make is stored here and stays '
                  'readable offline.',
            );
          }
          return _HistoryList(scans: scans);
        },
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Clear history?'),
        content: const Text(
          'This deletes every stored check. Your allergy terms and products '
          'are kept.',
        ),
        actions: <Widget>[
          TextButton(
            // Pop with the dialog's own context, not the outer one.
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      await ref.read(historyActionsProvider).clearAll();
    }
  }
}

class _HistoryList extends ConsumerWidget {
  const _HistoryList({required this.scans});

  final List<Scan> scans;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Object> rows = _withDayHeaders(scans);

    return ListView.builder(
      itemCount: rows.length + 1,
      itemBuilder: (BuildContext context, int index) {
        if (index == rows.length) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Keeping the last $kMaxScanHistory checks',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          );
        }

        final Object row = rows[index];
        if (row is String) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              row.toUpperCase(),
              style: Theme.of(context).textTheme.labelMedium,
            ),
          );
        }

        final Scan scan = row as Scan;
        return Dismissible(
          key: ValueKey<String>(scan.id),
          direction: DismissDirection.endToStart,
          background: ColoredBox(
            color: Theme.of(context).colorScheme.errorContainer,
            child: const Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: EdgeInsets.only(right: 16),
                child: Icon(Icons.delete_outline),
              ),
            ),
          ),
          onDismissed: (_) =>
              ref.read(historyActionsProvider).delete(scan.id),
          child: ListTile(
            leading: VerdictBadge(verdict: scan.verdict),
            title: Text(
              scan.productNameSnapshot ?? scan.barcode ?? 'text scan',
            ),
            subtitle: Text(
              '${Formatters.matchCountLabel(scan.matchCount)} · '
              '${Formatters.inputModeLabel(scan.inputMode)}',
            ),
            trailing: Text(Formatters.time(scan.scannedAt)),
            onTap: () => context.go('/history/${scan.id}'),
          ),
        );
      },
    );
  }

  /// Day headers interleaved with the scans, so one flat list renders both.
  static List<Object> _withDayHeaders(List<Scan> scans) {
    final List<Object> rows = <Object>[];
    String? currentDay;
    for (final Scan scan in scans) {
      final String day = Formatters.dayHeader(scan.scannedAt);
      if (day != currentDay) {
        currentDay = day;
        rows.add(day);
      }
      rows.add(scan);
    }
    return rows;
  }
}
