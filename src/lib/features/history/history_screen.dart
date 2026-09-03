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
import '../../l10n/app_localizations.dart';
import 'history_providers.dart';

/// Past checks, newest first, grouped by day. Opening one needs no network:
/// every row is a self-contained snapshot (R4.7).
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Scan>> history = ref.watch(scanHistoryProvider);
    final ScanVerdict? filter = ref.watch(historyFilterProvider);
    final AppLocalizations l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.shellHistoryLabel),
        actions: <Widget>[
          PopupMenuButton<ScanVerdict?>(
            icon: const Icon(Icons.filter_list),
            tooltip: l10n.historyFilterTooltip,
            initialValue: filter,
            onSelected: (ScanVerdict? verdict) =>
                ref.read(historyFilterProvider.notifier).state = verdict,
            itemBuilder: (BuildContext context) =>
                <PopupMenuEntry<ScanVerdict?>>[
                  PopupMenuItem<ScanVerdict?>(
                    child: Text(l10n.historyFilterAll),
                  ),
                  PopupMenuItem<ScanVerdict?>(
                    value: ScanVerdict.hit,
                    child: Text(Formatters.verdictLabel(l10n, ScanVerdict.hit)),
                  ),
                  PopupMenuItem<ScanVerdict?>(
                    value: ScanVerdict.noMatch,
                    child: Text(
                      Formatters.verdictLabel(l10n, ScanVerdict.noMatch),
                    ),
                  ),
                  PopupMenuItem<ScanVerdict?>(
                    value: ScanVerdict.unknown,
                    child: Text(
                      Formatters.verdictLabel(l10n, ScanVerdict.unknown),
                    ),
                  ),
                ],
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: l10n.historyClearTooltip,
            onPressed: () => _confirmClear(context, ref, l10n),
          ),
        ],
      ),
      body: history.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace _) =>
            ErrorView(message: l10n.historyLoadError(error.toString())),
        data: (List<Scan> scans) {
          if (scans.isEmpty) {
            return EmptyView(
              icon: Icons.history,
              title: l10n.historyEmptyTitle,
              message: l10n.historyEmptyMessage,
            );
          }
          return _HistoryList(scans: scans);
        },
      ),
    );
  }

  Future<void> _confirmClear(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(l10n.historyClearDialogTitle),
        content: Text(l10n.historyClearDialogMessage),
        actions: <Widget>[
          TextButton(
            // Pop with the dialog's own context, not the outer one.
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.historyClearConfirm),
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

class _HistoryList extends ConsumerWidget {
  const _HistoryList({required this.scans});

  final List<Scan> scans;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final List<Object> rows = withShopGroups(
      scans,
      ungroupedLabel: l10n.historyUngroupedLabel,
    );

    return ListView.builder(
      itemCount: rows.length + 1,
      itemBuilder: (BuildContext context, int index) {
        if (index == rows.length) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              l10n.historyRetentionNote(kMaxScanHistory),
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
              scan.name ??
                  scan.productNameSnapshot ??
                  scan.barcode ??
                  l10n.historyUnnamedScan,
            ),
            subtitle: Text(
              '${Formatters.matchCountLabel(l10n, scan.matchCount)} · '
              '${Formatters.inputModeLabel(l10n, scan.inputMode)}',
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
/// above one not visited in months — [ungroupedLabel] needs no special-casing
/// under this rule. Pure transform over the already-fetched, already
/// reverse-chronological list — no new query. Top-level (not a method on
/// the private `_HistoryList`) so it is unit-testable without a widget pump.
/// [ungroupedLabel] is passed in rather than hardcoded so this stays a pure,
/// context-free function while still rendering in the caller's language.
@visibleForTesting
List<Object> withShopGroups(
  List<Scan> scans, {
  required String ungroupedLabel,
}) {
  final Map<String, List<Scan>> byShop = <String, List<Scan>>{};
  for (final Scan scan in scans) {
    final String? shop = scan.shop?.trim();
    final String key = (shop == null || shop.isEmpty) ? ungroupedLabel : shop;
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
