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

/// A shop-group header, distinct from the day-header `String` rows so the
/// list's `is String` check keeps unambiguously matching day headers.
class ShopHeader {
  const ShopHeader(this.label);

  final String label;
}

const String _ungroupedShopLabel = 'Ungrouped';

class _HistoryList extends ConsumerWidget {
  const _HistoryList({required this.scans});

  final List<Scan> scans;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Object> rows = withShopGroups(scans);

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
        if (row is ShopHeader) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
            child: Text(
              row.label,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          );
        }
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
              scan.name ?? scan.productNameSnapshot ?? scan.barcode ?? 'text scan',
            ),
            subtitle: Text(
              '${Formatters.matchCountLabel(scan.matchCount)} · '
              '${Formatters.inputModeLabel(scan.inputMode)}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (scan.photoPath != null) ...<Widget>[
                  const Icon(Icons.photo_outlined, size: 16),
                  const SizedBox(width: 4),
                ],
                Text(Formatters.time(scan.scannedAt)),
              ],
            ),
            onTap: () => context.go('/history/${scan.id}'),
          ),
        );
      },
    );
  }

}

/// Shop headers interleaved with day-headers-within-shop, so scans sharing a
/// `shop` value are grouped together (§4, R7.12). Groups are ordered by
/// their own most-recent scan, so a shop visited five minutes ago sorts
/// above one not visited in months — "Ungrouped" needs no special-casing
/// under this rule. Pure transform over the already-fetched, already
/// reverse-chronological list — no new query. Top-level (not a method on
/// the private `_HistoryList`) so it is unit-testable without a widget pump.
@visibleForTesting
List<Object> withShopGroups(List<Scan> scans) {
  final Map<String, List<Scan>> byShop = <String, List<Scan>>{};
  for (final Scan scan in scans) {
    final String? shop = scan.shop?.trim();
    final String key = (shop == null || shop.isEmpty)
        ? _ungroupedShopLabel
        : shop;
    (byShop[key] ??= <Scan>[]).add(scan);
  }

  final List<String> orderedKeys = byShop.keys.toList()
    ..sort(
      (String a, String b) =>
          byShop[b]!.first.scannedAt.compareTo(byShop[a]!.first.scannedAt),
    );

  final List<Object> rows = <Object>[];
  for (final String key in orderedKeys) {
    rows.add(ShopHeader(key));
    rows.addAll(withDayHeaders(byShop[key]!));
  }
  return rows;
}

/// Day headers interleaved with the scans, so one flat list renders both.
@visibleForTesting
List<Object> withDayHeaders(List<Scan> scans) {
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
