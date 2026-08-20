import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/allergen_term.dart';
import '../../core/models/scan.dart';
import '../../core/providers.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/scan_capabilities.dart';
import '../../core/widgets/verdict_banner.dart';
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

    return Scaffold(
      appBar: AppBar(title: const Text('AllergyScanner')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          // Hidden, not disabled, where the platform cannot deliver it (R3.1).
          if (capabilities.canScanBarcode)
            _ActionCard(
              icon: Icons.qr_code_scanner,
              title: 'Scan barcode',
              subtitle: 'Look up the product',
              onTap: () => context.go('/scan/barcode'),
            ),
          if (capabilities.canRecognizeText)
            _ActionCard(
              icon: Icons.document_scanner_outlined,
              title: 'Scan ingredient list',
              subtitle: 'Read the text on the pack',
              onTap: () => context.go('/scan/text'),
            ),
          _ActionCard(
            icon: Icons.keyboard_alt_outlined,
            title: 'Enter manually',
            subtitle: 'Barcode or ingredient text',
            onTap: () => context.go('/scan/manual'),
          ),
          const SizedBox(height: 8),
          if (capabilities.isManualOnly)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Camera scanning is not available on this platform — use '
                '"Enter manually".',
              ),
            ),
          _TermSummary(activeTerms: activeTerms),
          if (recent.isNotEmpty) ...<Widget>[
            const SizedBox(height: 24),
            Text('Recent', style: Theme.of(context).textTheme.titleMedium),
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

    // With no terms every check ends in "could not be checked" (R5.7), so this
    // is a warning rather than a count.
    if (activeTerms.isEmpty) {
      return Card(
        color: colors.errorContainer,
        child: ListTile(
          leading: Icon(Icons.warning_amber_rounded, color: colors.onErrorContainer),
          title: Text(
            'No terms yet — add one first',
            style: TextStyle(color: colors.onErrorContainer),
          ),
          subtitle: Text(
            'Without a term there is nothing to check against.',
            style: TextStyle(color: colors.onErrorContainer),
          ),
          onTap: () => context.go('/allergies'),
        ),
      );
    }

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.list_alt),
      title: Text('Your list: ${activeTerms.length} active terms'),
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
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: VerdictBadge(verdict: scan.verdict),
      title: Text(scan.productNameSnapshot ?? _fallbackTitle(scan)),
      subtitle: Text(
        '${Formatters.matchCountLabel(scan.matchCount)} · '
        '${Formatters.inputModeLabel(scan.inputMode)}',
      ),
      trailing: Text(Formatters.time(scan.scannedAt)),
      onTap: onTap,
    );
  }

  static String _fallbackTitle(Scan scan) => scan.barcode ?? 'text scan';
}
