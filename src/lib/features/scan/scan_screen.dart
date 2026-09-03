import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/allergen_term.dart';
import '../../core/models/scan.dart';
import '../../core/providers.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/scan_capabilities.dart';
import '../../core/widgets/verdict_banner.dart';
import '../../l10n/app_localizations.dart';
import 'scan_providers.dart';

/// Start destination: the three ways into the one scan pipeline, plus the
/// newest results.
class ScanScreen extends ConsumerWidget {
  const ScanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ScanCapabilities capabilities = ref.watch(scanCapabilitiesProvider);
    final List<AllergenTerm> activeTerms =
        ref.watch(activeAllergenTermsProvider).value ?? const <AllergenTerm>[];
    final List<Scan> recent =
        ref.watch(recentScansProvider).value ?? const <Scan>[];
    final AppLocalizations l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.appTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          // Hidden, not disabled, where the platform cannot deliver it (R3.1).
          if (capabilities.canScanBarcode)
            _ActionCard(
              icon: Icons.qr_code_scanner,
              title: l10n.scanBarcodeTitle,
              subtitle: l10n.scanBarcodeSubtitle,
              onTap: () => context.go('/scan/barcode'),
            ),
          if (capabilities.canRecognizeText)
            _ActionCard(
              icon: Icons.document_scanner_outlined,
              title: l10n.resultScanIngredientListAction,
              subtitle: l10n.scanTextSubtitle,
              onTap: () => context.go('/scan/text'),
            ),
          _ActionCard(
            icon: Icons.keyboard_alt_outlined,
            title: l10n.scanManualTitle,
            subtitle: l10n.scanManualSubtitle,
            onTap: () => context.go('/scan/manual'),
          ),
          const SizedBox(height: 8),
          if (capabilities.isManualOnly)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(l10n.scanManualOnlyNotice),
            ),
          _TermSummary(activeTerms: activeTerms),
          if (recent.isNotEmpty) ...<Widget>[
            const SizedBox(height: 24),
            Text(
              l10n.scanRecentHeading,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Divider(),
            ...recent.map(
              (Scan scan) => _RecentTile(
                scan: scan,
                onTap: () => context.go('/scan/result/${scan.id}'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon, size: 32),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _TermSummary extends StatelessWidget {
  const _TermSummary({required this.activeTerms});

  final List<AllergenTerm> activeTerms;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final AppLocalizations l10n = AppLocalizations.of(context)!;

    // With no terms every check ends in "could not be checked" (R5.7), so this
    // is a warning rather than a count.
    if (activeTerms.isEmpty) {
      return Card(
        color: colors.errorContainer,
        child: ListTile(
          leading: Icon(Icons.warning_amber_rounded, color: colors.onErrorContainer),
          title: Text(
            l10n.scanNoTermsTitle,
            style: TextStyle(color: colors.onErrorContainer),
          ),
          subtitle: Text(
            l10n.scanNoTermsSubtitle,
            style: TextStyle(color: colors.onErrorContainer),
          ),
          onTap: () => context.go('/allergies'),
        ),
      );
    }

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.list_alt),
      title: Text(l10n.scanActiveTermsSummary(activeTerms.length)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.go('/allergies'),
    );
  }
}

class _RecentTile extends StatelessWidget {
  const _RecentTile({required this.scan, required this.onTap});

  final Scan scan;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: VerdictBadge(verdict: scan.verdict),
      title: Text(scan.productNameSnapshot ?? _fallbackTitle(l10n, scan)),
      subtitle: Text(
        '${Formatters.matchCountLabel(l10n, scan.matchCount)} · '
        '${Formatters.inputModeLabel(l10n, scan.inputMode)}',
      ),
      trailing: Text(Formatters.time(scan.scannedAt)),
      onTap: onTap,
    );
  }

  static String _fallbackTitle(AppLocalizations l10n, Scan scan) =>
      scan.barcode ?? l10n.historyUnnamedScan;
}
