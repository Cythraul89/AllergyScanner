import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/calculators/allergen_matcher.dart';
import '../../core/calculators/text_normalizer.dart';
import '../../core/models/allergen_term.dart';
import '../../core/models/enums.dart';
import '../../core/models/product.dart';
import '../../core/models/scan.dart';
import '../../core/providers.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/scan_capabilities.dart';
import '../../core/widgets/error_view.dart';
import '../../core/widgets/highlighted_text.dart';
import '../../core/widgets/verdict_banner.dart';
import '../../l10n/app_localizations.dart';
import '../history/history_providers.dart';
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
    final AppLocalizations l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.resultTitle),
        actions: <Widget>[
          if (result.value != null)
            PopupMenuButton<String>(
              onSelected: (String action) =>
                  _onMenuAction(context, ref, action, result.value!, l10n),
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  value: 'share',
                  child: Text(l10n.resultShareAction),
                ),
                PopupMenuItem<String>(
                  value: 'delete',
                  child: Text(l10n.resultDeleteAction),
                ),
              ],
            ),
        ],
      ),
      body: result.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace _) =>
            ErrorView(message: l10n.resultLoadError(error.toString())),
        data: (ScanResult? value) {
          if (value == null) {
            return ErrorView(message: l10n.resultNotFound);
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
    AppLocalizations l10n,
  ) async {
    switch (action) {
      case 'share':
        await SharePlus.instance.share(
          ShareParams(text: _asShareText(result, l10n)),
        );
      case 'delete':
        // Routed through HistoryActions, not the DAO directly, so photo
        // cleanup (§4) happens the same way regardless of where a scan is
        // deleted from.
        await ref.read(historyActionsProvider).delete(result.scan.id);
        if (context.mounted) context.pop();
    }
  }

  static String _asShareText(ScanResult result, AppLocalizations l10n) {
    final StringBuffer buffer = StringBuffer()
      ..writeln(
        'AllergyScanner — '
        '${Formatters.verdictTitle(l10n, result.scan.verdict)}',
      )
      ..writeln(result.scan.productNameSnapshot ?? result.scan.barcode ?? '')
      ..writeln();
    for (final ScanMatch match in result.matches) {
      buffer.writeln('• ${match.termSnapshot}');
    }
    buffer
      ..writeln()
      ..writeln(l10n.resultSafetyReminder);
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
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ScanCapabilities capabilities = ref.watch(scanCapabilitiesProvider);
    final List<AllergenTerm> allTerms =
        ref.watch(allAllergenTermsProvider).value ?? const <AllergenTerm>[];

    // Offsets refer to the normalised text, so the context excerpts are cut
    // from the same string the matcher searched (R5.4).
    final String normalized = TextNormalizer.normalize(scan.evaluatedText);
    final List<List<ScanMatch>> matchBuckets = bucketMatchesByGroup(
      result.matches,
      allTerms,
    );
    final Map<String, Color> termColors = ref.watch(allergenTermColorsProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        VerdictBanner(
          verdict: scan.verdict,
          detail: _verdictDetail(l10n, scan),
        ),
        const SizedBox(height: 16),

        if (scan.name != null || scan.shop != null || scan.photoPath != null)
          _ScanDetailsSummary(scan: scan),

        if (scan.verdict == ScanVerdict.unknown)
          _UnknownActions(capabilities: capabilities, scan: scan),

        if (product != null || scan.productNameSnapshot != null) ...<Widget>[
          Text(
            _productLine(l10n, scan, product),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            _provenanceLine(l10n, scan, product),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
        ],

        if (matchBuckets.isNotEmpty) ...<Widget>[
          Text(l10n.resultMatchesHeading, style: theme.textTheme.titleMedium),
          const Divider(),
          ...matchBuckets.map(
            (List<ScanMatch> bucket) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    bucket.first.termSnapshot,
                    style: theme.textTheme.titleSmall?.copyWith(
                      // The group's own colour when it has one, so a match
                      // here and the same match highlighted in the evaluated
                      // text below read as the same thing (R7.16).
                      color:
                          termColors[bucket.first.allergenTermId] ??
                          theme.colorScheme.error,
                    ),
                  ),
                  // The surrounding text is shown so a false positive such as
                  // "nut" inside "coconut" is recognisable (R5.6).
                  Text(
                    '"${AllergenMatcher.contextFor(normalized, bucket.first.startOffset, bucket.first.endOffset)}"',
                    style: theme.textTheme.bodySmall,
                  ),
                  // Other names from the same group found in this text (§11
                  // item 1) — grouping is a display convenience only, the
                  // matcher itself still matches each name independently.
                  if (bucket.length > 1)
                    Text(
                      l10n.resultAlsoMatched(
                        bucket
                            .skip(1)
                            .map((ScanMatch m) => m.termSnapshot)
                            .join(', '),
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                      ),
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
              title: l10n.resultDeclaredByOff,
              tags: product.allergensTags,
            ),
          if (product.tracesTags.isNotEmpty)
            _TagSection(title: l10n.resultMayContain, tags: product.tracesTags),
          if (product.allergensTags.isNotEmpty ||
              product.tracesTags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 12),
              child: Text(
                l10n.resultDeclarationsNote,
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],

        ExpansionTile(
          title: Text(l10n.resultEvaluatedTextTitle),
          tilePadding: EdgeInsets.zero,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: scan.evaluatedText.isEmpty
                  ? SelectableText(
                      l10n.resultNoTextAvailable,
                      style: theme.textTheme.bodySmall,
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        // The normalised form, not scan.evaluatedText: the
                        // stored match offsets index into it (R5.4), so this
                        // is the only string a highlight can be placed on
                        // without recomputing the match.
                        HighlightedText(
                          text: normalized,
                          highlights: result.matches
                              .map(
                                (ScanMatch m) => TextHighlightRange(
                                  start: m.startOffset,
                                  end: m.endOffset,
                                  label: m.termSnapshot,
                                  color: termColors[m.allergenTermId],
                                ),
                              )
                              .toList(growable: false),
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.resultNormalisedTextNote,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),

        const SizedBox(height: 8),
        Text(l10n.resultSafetyReminder, style: theme.textTheme.bodySmall),
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
                child: Text(l10n.resultCorrectProductAction),
              ),
            OutlinedButton(
              onPressed: () => context.go('/scan/result/${scan.id}/details'),
              child: Text(l10n.resultEditDetailsAction),
            ),
            OutlinedButton(
              onPressed: () => context.go('/scan'),
              child: Text(l10n.resultNewScanAction),
            ),
          ],
        ),
      ],
    );
  }

  String? _verdictDetail(AppLocalizations l10n, Scan scan) {
    switch (scan.verdict) {
      case ScanVerdict.hit:
        return Formatters.matchCountLabel(l10n, scan.matchCount);
      case ScanVerdict.noMatch:
        return l10n.resultNoMatchDetail;
      case ScanVerdict.unknown:
        return _unknownReason(l10n);
    }
  }

  String _unknownReason(AppLocalizations l10n) {
    switch (lookupProblem) {
      case ScanLookupProblem.productNotFound:
        return l10n.resultUnknownProductNotFound;
      case ScanLookupProblem.serverUnreachable:
        return l10n.resultUnknownServerUnreachable;
      case ScanLookupProblem.lookupFailed:
        return l10n.resultUnknownLookupFailed;
      case ScanLookupProblem.remoteLookupDisabled:
        return l10n.resultUnknownRemoteLookupDisabled;
      case ScanLookupProblem.noIngredientText:
        return l10n.resultUnknownNoIngredientText;
      case null:
        return l10n.resultUnknownGeneric;
    }
  }

  static String _productLine(
    AppLocalizations l10n,
    Scan scan,
    Product? product,
  ) {
    final List<String> parts = <String>[
      product?.productName ?? scan.productNameSnapshot ?? '',
      product?.brands ?? '',
      product?.quantity ?? '',
    ].where((String part) => part.isNotEmpty).toList(growable: false);
    return parts.isEmpty
        ? (scan.barcode ?? l10n.resultTextScanFallback)
        : parts.join(' · ');
  }

  static String _provenanceLine(
    AppLocalizations l10n,
    Scan scan,
    Product? product,
  ) {
    if (product == null) {
      return Formatters.inputModeLabel(l10n, scan.inputMode);
    }
    if (product.hasManualOverride) {
      return l10n.resultCorrectedByYou;
    }
    final DateTime? fetched = product.fetchedAt;
    if (product.source == ProductSource.openFoodFacts && fetched != null) {
      return l10n.resultOffFetchedOn(Formatters.date(fetched));
    }
    return Formatters.inputModeLabel(l10n, scan.inputMode);
  }
}

/// The user-entered name/shop/photo, when any are set (§4 "Edit details").
class _ScanDetailsSummary extends ConsumerWidget {
  const _ScanDetailsSummary({required this.scan});

  final Scan scan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final String? photoPath = scan.photoPath;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (photoPath != null) ...<Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: FutureBuilder<File>(
                future: ref.read(scanPhotoServiceProvider).resolve(photoPath),
                builder: (BuildContext context, AsyncSnapshot<File> snapshot) {
                  final File? file = snapshot.data;
                  if (file == null) {
                    return const SizedBox(width: 64, height: 64);
                  }
                  return Image.file(
                    file,
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (scan.name != null)
                  Text(scan.name!, style: theme.textTheme.titleSmall),
                if (scan.shop != null)
                  Text(scan.shop!, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The next steps offered when nothing could be checked.
class _UnknownActions extends StatelessWidget {
  const _UnknownActions({required this.capabilities, required this.scan});

  final ScanCapabilities capabilities;
  final Scan scan;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        children: <Widget>[
          if (capabilities.canRecognizeText)
            FilledButton(
              onPressed: () => context.go('/scan/text'),
              child: Text(l10n.resultScanIngredientListAction),
            ),
          OutlinedButton(
            onPressed: () => context.go('/scan/review', extra: ''),
            child: Text(l10n.resultEnterTextManuallyAction),
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

/// Buckets [matches] whose term belongs to the same allergen group together,
/// so two synonyms found in the same text (e.g. "Hazelnut" and "Haselnuss")
/// show as one entry with an "also matched" line, instead of two unrelated
/// -looking rows. A match whose term was deleted (`allergenTermId == null`)
/// or is ungrouped renders standalone, exactly as before grouping existed.
/// Display-only: the matcher and the persisted `ScanMatch` rows are
/// unchanged (§11 item 1).
@visibleForTesting
List<List<ScanMatch>> bucketMatchesByGroup(
  List<ScanMatch> matches,
  List<AllergenTerm> terms,
) {
  final Map<String, String?> groupIdByTermId = <String, String?>{
    for (final AllergenTerm term in terms) term.id: term.groupId,
  };

  final List<List<ScanMatch>> buckets = <List<ScanMatch>>[];
  final Map<String, List<ScanMatch>> byGroupId = <String, List<ScanMatch>>{};

  for (final ScanMatch match in matches) {
    final String? termId = match.allergenTermId;
    final String? groupId = termId == null ? null : groupIdByTermId[termId];
    if (groupId == null) {
      buckets.add(<ScanMatch>[match]);
      continue;
    }
    final List<ScanMatch>? existing = byGroupId[groupId];
    if (existing == null) {
      final List<ScanMatch> bucket = <ScanMatch>[match];
      byGroupId[groupId] = bucket;
      buckets.add(bucket);
    } else {
      existing.add(match);
    }
  }

  buckets.sort(
    (List<ScanMatch> a, List<ScanMatch> b) =>
        a.first.startOffset.compareTo(b.first.startOffset),
  );
  return buckets;
}
