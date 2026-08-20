import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/calculators/allergen_matcher.dart';
import '../../core/calculators/text_normalizer.dart';
import '../../core/models/enums.dart';
import '../../core/models/product.dart';
import '../../core/models/scan.dart';
import '../../core/providers.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/scan_capabilities.dart';
import '../../core/widgets/error_view.dart';
import '../../core/widgets/verdict_banner.dart';
import '../scan/scan_actions.dart';
import 'result_providers.dart';

/// The result of one check — used for a fresh scan and for a history entry,
/// deliberately the same widget so a stored record looks identical to what the
/// user saw at scan time (doc/ARCHITECTURE.md §5.11).
class ScanResultScreen extends ConsumerWidget {
  const ScanResultScreen({
    required this.scanId,
    this.lookupProblem,
    super.key,
  });

  final String scanId;

  /// Only known for a live scan; a history entry stores the verdict, not the
  /// reason it could not be checked.
  final ScanLookupProblem? lookupProblem;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<ScanResult?> result = ref.watch(
      scanResultProvider(scanId),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Result'),
        actions: <Widget>[
          if (result.value != null)
            PopupMenuButton<String>(
              onSelected: (String action) =>
                  _onMenuAction(context, ref, action, result.value!),
              itemBuilder: (BuildContext context) =>
                  const <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(
                      value: 'share',
                      child: Text('Share result as text'),
                    ),
                    PopupMenuItem<String>(
                      value: 'delete',
                      child: Text('Delete this scan'),
                    ),
                  ],
            ),
        ],
      ),
      body: result.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace _) =>
            ErrorView(message: 'Could not load this result: $error'),
        data: (ScanResult? value) {
          if (value == null) {
            return const ErrorView(message: 'This scan no longer exists.');
          }
          return _ResultBody(result: value, lookupProblem: lookupProblem);
        },
      ),
    );
  }

  Future<void> _onMenuAction(
    BuildContext context,
    WidgetRef ref,
    String action,
    ScanResult result,
  ) async {
    switch (action) {
      case 'share':
        await SharePlus.instance.share(
          ShareParams(text: _asShareText(result)),
        );
      case 'delete':
        await ref.read(scanDaoProvider).deleteById(result.scan.id);
        if (context.mounted) context.pop();
    }
  }

  static String _asShareText(ScanResult result) {
    final StringBuffer buffer = StringBuffer()
      ..writeln('AllergyScanner — ${Formatters.verdictTitle(result.scan.verdict)}')
      ..writeln(result.scan.productNameSnapshot ?? result.scan.barcode ?? '')
      ..writeln();
    for (final ScanMatch match in result.matches) {
      buffer.writeln('• ${match.termSnapshot}');
    }
    buffer
      ..writeln()
      ..writeln(
        'This is a text match, not a safety assessment. '
        'Always read the packaging.',
      );
    return buffer.toString();
  }
}

class _ResultBody extends ConsumerWidget {
  const _ResultBody({required this.result, this.lookupProblem});

  final ScanResult result;
  final ScanLookupProblem? lookupProblem;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Scan scan = result.scan;
    final Product? product = result.product;
    final ThemeData theme = Theme.of(context);
    final ScanCapabilities capabilities = ref.watch(scanCapabilitiesProvider);

    // Offsets refer to the normalised text, so the context excerpts are cut
    // from the same string the matcher searched (R5.4).
    final String normalized = TextNormalizer.normalize(scan.evaluatedText);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        VerdictBanner(verdict: scan.verdict, detail: _verdictDetail(scan)),
        const SizedBox(height: 16),

        if (scan.verdict == ScanVerdict.unknown)
          _UnknownActions(capabilities: capabilities, scan: scan),

        if (product != null || scan.productNameSnapshot != null) ...<Widget>[
          Text(
            _productLine(scan, product),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            _provenanceLine(scan, product),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
        ],

        if (result.matches.isNotEmpty) ...<Widget>[
          Text('Matches', style: theme.textTheme.titleMedium),
          const Divider(),
          ...result.matches.map(
            (ScanMatch match) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    match.termSnapshot,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                  // The surrounding text is shown so a false positive such as
                  // "nut" inside "coconut" is recognisable (R5.6).
                  Text(
                    '"${AllergenMatcher.contextFor(normalized, match.startOffset, match.endOffset)}"',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],

        if (product != null) ...<Widget>[
          if (product.allergensTags.isNotEmpty)
            _TagSection(
              title: 'Declared by Open Food Facts',
              tags: product.allergensTags,
            ),
          if (product.tracesTags.isNotEmpty)
            _TagSection(title: 'May contain', tags: product.tracesTags),
          if (product.allergensTags.isNotEmpty ||
              product.tracesTags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 12),
              child: Text(
                'These declarations are shown for information. They are not '
                'matched against your list.',
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],

        ExpansionTile(
          title: const Text('Evaluated text'),
          tilePadding: EdgeInsets.zero,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SelectableText(
                scan.evaluatedText.isEmpty
                    ? 'No ingredient text was available.'
                    : scan.evaluatedText,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),

        const SizedBox(height: 8),
        Text(
          'This is a text match, not a safety assessment. Always read the '
          'packaging.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 16),

        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: <Widget>[
            if (scan.barcode != null)
              OutlinedButton(
                onPressed: () => context.go(
                  '/scan/result/${scan.id}/product',
                  extra: scan.barcode,
                ),
                child: const Text('Correct product data'),
              ),
            OutlinedButton(
              onPressed: () => context.go('/scan'),
              child: const Text('New scan'),
            ),
          ],
        ),
      ],
    );
  }

  String? _verdictDetail(Scan scan) {
    switch (scan.verdict) {
      case ScanVerdict.hit:
        return Formatters.matchCountLabel(scan.matchCount);
      case ScanVerdict.noMatch:
        return 'Checked the ingredient text against your active terms.';
      case ScanVerdict.unknown:
        return _unknownReason();
    }
  }

  String _unknownReason() {
    switch (lookupProblem) {
      case ScanLookupProblem.productNotFound:
        return 'This barcode is not in Open Food Facts.';
      case ScanLookupProblem.serverUnreachable:
        return 'Open Food Facts could not be reached — a retry may help.';
      case ScanLookupProblem.lookupFailed:
        return 'The lookup failed.';
      case ScanLookupProblem.remoteLookupDisabled:
        return 'Online lookup is switched off and this product is not stored '
            'locally.';
      case ScanLookupProblem.noIngredientText:
        return 'No ingredient text is available for this product.';
      case null:
        return 'There was no ingredient text to check, or your list is empty.';
    }
  }

  static String _productLine(Scan scan, Product? product) {
    final List<String> parts = <String>[
      product?.productName ?? scan.productNameSnapshot ?? '',
      product?.brands ?? '',
      product?.quantity ?? '',
    ].where((String part) => part.isNotEmpty).toList(growable: false);
    return parts.isEmpty ? (scan.barcode ?? 'Text scan') : parts.join(' · ');
  }

  static String _provenanceLine(Scan scan, Product? product) {
    if (product == null) {
      return Formatters.inputModeLabel(scan.inputMode);
    }
    if (product.hasManualOverride) {
      return 'Corrected by you';
    }
    final DateTime? fetched = product.fetchedAt;
    if (product.source == ProductSource.openFoodFacts && fetched != null) {
      return 'Open Food Facts, fetched ${Formatters.date(fetched)}';
    }
    return Formatters.inputModeLabel(scan.inputMode);
  }
}

/// The next steps offered when nothing could be checked.
class _UnknownActions extends StatelessWidget {
  const _UnknownActions({required this.capabilities, required this.scan});

  final ScanCapabilities capabilities;
  final Scan scan;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        children: <Widget>[
          if (capabilities.canRecognizeText)
            FilledButton(
              onPressed: () => context.go('/scan/text'),
              child: const Text('Scan ingredient list'),
            ),
          OutlinedButton(
            onPressed: () => context.go('/scan/review', extra: ''),
            child: const Text('Enter text manually'),
          ),
        ],
      ),
    );
  }
}

class _TagSection extends StatelessWidget {
  const _TagSection({required this.title, required this.tags});

  final String title;
  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 8),
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: tags
              .map((String tag) => Chip(label: Text(_readable(tag))))
              .toList(growable: false),
        ),
      ],
    );
  }

  /// Open Food Facts tags look like `en:milk`; the language prefix is noise here.
  static String _readable(String tag) {
    final int separator = tag.indexOf(':');
    return separator < 0 ? tag : tag.substring(separator + 1);
  }
}
