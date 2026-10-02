import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/calculators/allergen_matcher.dart';
import '../../core/calculators/ingredient_marker_detector.dart';
import '../../core/models/allergen_term.dart';
import '../../core/models/enums.dart';
import '../../core/models/scan_input.dart';
import '../../core/providers.dart';
import '../../core/utils/scan_capabilities.dart';
import '../../core/widgets/highlighted_text.dart';
import '../../l10n/app_localizations.dart';
import 'scan_actions.dart';
import 'scan_providers.dart';

/// Editable ingredient text before it is checked.
///
/// Recognition errors are fixed here rather than by re-scanning (R7.3). The
/// text must contain a localised ingredients marker before *Check* is
/// enabled (R5.8/R5.9) — this gate lives entirely here, before
/// `ScanActions.evaluate` is ever called, never inside `ScanActions` itself
/// (doc/ARCHITECTURE.md §5.9).
class TextReviewScreen extends ConsumerStatefulWidget {
  const TextReviewScreen({required this.initialText, super.key});

  final String initialText;

  @override
  ConsumerState<TextReviewScreen> createState() => _TextReviewScreenState();
}

class _TextReviewScreenState extends ConsumerState<TextReviewScreen> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ScanCapabilities capabilities = ref.watch(scanCapabilitiesProvider);
    final List<AllergenTerm> activeTerms =
        ref.watch(activeAllergenTermsProvider).value ?? const <AllergenTerm>[];
    final bool wasRecognised = widget.initialText.isNotEmpty;
    // Recomputed on every keystroke (onChanged already triggers a rebuild) —
    // no debounce, same precedent as term_edit_screen.dart's live validation.
    final MarkerDetectionResult marker = IngredientMarkerDetector.detect(
      _controller.text,
    );
    final AppLocalizations l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.reviewTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(
            wasRecognised ? l10n.reviewRecognisedHint : l10n.reviewNoTextHint,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            minLines: 6,
            maxLines: 16,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          if (capabilities.canRecognizeText)
            OutlinedButton.icon(
              onPressed: () => context.go('/scan/text'),
              icon: const Icon(Icons.document_scanner_outlined),
              label: Text(l10n.reviewRescanAction),
            ),
          const SizedBox(height: 16),
          switch (marker) {
            MarkerFound() => _DetectedSectionPreview(
              marker: marker,
              activeTerms: activeTerms,
            ),
            MarkerNotFound() => const _NoMarkerWarning(),
          },
          const SizedBox(height: 24),
          FilledButton(
            onPressed: marker is MarkerFound && !_busy ? _check : null,
            child: _busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.reviewCheckAction),
          ),
        ],
      ),
    );
  }

  Future<void> _check() async {
    // Defense in depth: the button is already disabled without a marker, but
    // this guards any future call path that could reach _check directly.
    if (IngredientMarkerDetector.detect(_controller.text) is! MarkerFound) {
      return;
    }
    setState(() => _busy = true);

    final ScanOutcome outcome = await ref.read(scanActionsProvider).evaluate(
      TextInput(
        // The full, unmodified text — the detected section only scopes the
        // display preview above, never what is actually persisted/evaluated.
        text: _controller.text,
        // The mode records where the text came from, which the result view and
        // the history show as provenance.
        mode: widget.initialText.isEmpty
            ? ScanInputMode.manualText
            : ScanInputMode.ocr,
      ),
    );

    if (!mounted) return;
    context.go('/scan/result/${outcome.scanId}', extra: outcome.lookupProblem);
  }
}

class _NoMarkerWarning extends StatelessWidget {
  const _NoMarkerWarning();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(Icons.info_outline),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                AppLocalizations.of(context)!.reviewNoMarkerWarning,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetectedSectionPreview extends ConsumerWidget {
  const _DetectedSectionPreview({
    required this.marker,
    required this.activeTerms,
  });

  final MarkerFound marker;
  final List<AllergenTerm> activeTerms;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final MatchOutcome outcome = AllergenMatcher.match(
      text: marker.sectionText,
      activeTerms: activeTerms,
    );
    final Map<String, Color> termColors = ref.watch(allergenTermColorsProvider);
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context)!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              l10n.reviewSectionDetectedTitle,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              outcome.matches.isEmpty
                  ? l10n.reviewSectionNoMatch
                  : l10n.reviewSectionMatchCount(outcome.matches.length),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            HighlightedText(
              text: outcome.normalizedText,
              highlights: outcome.matches
                  .map(
                    (AllergenMatch m) => TextHighlightRange(
                      start: m.startOffset,
                      end: m.endOffset,
                      label: m.term,
                      color: termColors[m.termId],
                    ),
                  )
                  .toList(growable: false),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.reviewPreviewNote,
              style: theme.textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
