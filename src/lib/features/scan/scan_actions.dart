import 'package:uuid/uuid.dart';

import '../../core/calculators/allergen_matcher.dart';
import '../../core/constants.dart';
import '../../core/database/daos/allergen_term_dao.dart';
import '../../core/database/daos/product_dao.dart';
import '../../core/database/daos/scan_dao.dart';
import '../../core/database/daos/settings_dao.dart';
import '../../core/models/allergen_term.dart';
import '../../core/models/app_settings.dart';
import '../../core/models/enums.dart';
import '../../core/models/product.dart';
import '../../core/models/scan.dart';
import '../../core/models/scan_input.dart';
import '../../core/services/log_service.dart';
import '../../core/services/open_food_facts_service.dart';

/// Why a barcode could not be resolved. Only relevant for the live result view;
/// history stores the verdict, not the reason.
enum ScanLookupProblem {
  productNotFound,
  serverUnreachable,
  lookupFailed,
  remoteLookupDisabled,
  noIngredientText,
}

class ScanOutcome {
  const ScanOutcome({required this.scanId, this.lookupProblem});

  final String scanId;
  final ScanLookupProblem? lookupProblem;
}

/// The one place where a check happens (doc/ARCHITECTURE.md §4.1, §5.9).
///
/// Barcode, OCR and manual input all end up here, so none of them can forget to
/// normalise, to persist, or to prune the history.
class ScanActions {
  ScanActions({
    required AllergenTermDao allergenTermDao,
    required ProductDao productDao,
    required ScanDao scanDao,
    required SettingsDao settingsDao,
    required OpenFoodFactsService openFoodFacts,
    required LogService log,
    Uuid uuid = const Uuid(),
    DateTime Function()? now,
  }) : _allergenTermDao = allergenTermDao,
       _productDao = productDao,
       _scanDao = scanDao,
       _settingsDao = settingsDao,
       _openFoodFacts = openFoodFacts,
       _log = log,
       _uuid = uuid,
       _now = now ?? DateTime.now;

  final AllergenTermDao _allergenTermDao;
  final ProductDao _productDao;
  final ScanDao _scanDao;
  final SettingsDao _settingsDao;
  final OpenFoodFactsService _openFoodFacts;
  final LogService _log;
  final Uuid _uuid;
  final DateTime Function() _now;

  Future<ScanOutcome> evaluate(ScanInput input) async {
    // Read settings fresh instead of taking a cached snapshot — a stale
    // `remoteLookupEnabled` would make an offline-only user hit the network.
    final AppSettings settings = await _settingsDao.get();

    late final _Resolved resolved;
    switch (input) {
      case BarcodeInput():
        resolved = await _resolveBarcode(input, settings);
      case TextInput():
        resolved = _Resolved(text: input.text, mode: input.mode);
    }

    return _persist(
      scanId: _uuid.v4(),
      scannedAt: _now(),
      resolved: resolved,
    );
  }

  /// Re-runs the check for an existing scan, keeping its id and its place in
  /// the history — used after the user corrects the product data.
  Future<ScanOutcome> reevaluate(String scanId) async {
    final ScanResult? existing = await _scanDao.findResult(scanId);
    if (existing == null) {
      throw StateError('Cannot re-evaluate unknown scan $scanId');
    }

    final Scan scan = existing.scan;
    Product? product;
    String text = scan.evaluatedText;

    final String? barcode = scan.barcode;
    if (barcode != null) {
      product = await _productDao.findByBarcode(barcode);
      if (product != null && product.hasIngredients) {
        text = product.ingredientsText!;
      }
    }

    return _persist(
      scanId: scan.id,
      scannedAt: scan.scannedAt,
      resolved: _Resolved(
        text: text,
        mode: scan.inputMode,
        barcode: barcode,
        product: product,
      ),
    );
  }

  Future<_Resolved> _resolveBarcode(
    BarcodeInput input,
    AppSettings settings,
  ) async {
    final String barcode = input.barcode.trim();
    Product? product = await _productDao.findByBarcode(barcode);
    ScanLookupProblem? problem;

    final bool needsRemote =
        product == null || !product.hasIngredients || product.isStale(_now());

    if (needsRemote) {
      if (!settings.remoteLookupEnabled) {
        if (product == null) {
          problem = ScanLookupProblem.remoteLookupDisabled;
        }
      } else {
        final OffResult result = await _openFoodFacts.fetchProduct(
          barcode,
          preferredLanguage: settings.preferredIngredientsLanguage,
        );
        switch (result) {
          case OffSuccess(product: final Product fetched):
            final bool written = await _productDao.upsertFromRemote(fetched);
            // A manual override refuses the write and keeps winning (R4.4).
            product = written ? fetched : product;
          case OffNotFound():
            if (product == null) {
              problem = ScanLookupProblem.productNotFound;
            }
          case OffTransient():
            if (product == null) {
              problem = ScanLookupProblem.serverUnreachable;
            }
          case OffFailure(message: final String message):
            _log.warn('Barcode $barcode lookup failed: $message');
            if (product == null) {
              problem = ScanLookupProblem.lookupFailed;
            }
        }
      }
    }

    if (problem == null && (product == null || !product.hasIngredients)) {
      problem = ScanLookupProblem.noIngredientText;
    }

    return _Resolved(
      text: product?.ingredientsText ?? '',
      mode: input.mode,
      barcode: barcode,
      product: product,
      problem: problem,
    );
  }

  Future<ScanOutcome> _persist({
    required String scanId,
    required DateTime scannedAt,
    required _Resolved resolved,
  }) async {
    final List<AllergenTerm> terms = await _allergenTermDao.getActive();
    final MatchOutcome outcome = AllergenMatcher.match(
      text: resolved.text,
      activeTerms: terms,
    );

    final List<ScanMatch> matches = outcome.matches
        .map(
          (AllergenMatch match) => ScanMatch(
            id: _uuid.v4(),
            scanId: scanId,
            allergenTermId: match.termId,
            termSnapshot: match.term,
            matchedText: match.matchedText,
            startOffset: match.startOffset,
            endOffset: match.endOffset,
          ),
        )
        .toList(growable: false);

    // Written before the result view opens, so a crash cannot lose it (R7.7).
    await _scanDao.insertWithMatches(
      scan: Scan(
        id: scanId,
        scannedAt: scannedAt,
        inputMode: resolved.mode,
        barcode: resolved.barcode,
        productNameSnapshot: resolved.product?.productName,
        evaluatedText: resolved.text,
        verdict: outcome.verdict,
        matchCount: matches.length,
      ),
      matches: matches,
      historyLimit: kMaxScanHistory,
    );

    _log.info(
      'Scan $scanId: ${outcome.verdict.name}, ${matches.length} match(es), '
      '${terms.length} active term(s)',
    );

    return ScanOutcome(scanId: scanId, lookupProblem: resolved.problem);
  }
}

/// What the pipeline knows once the input has been turned into text.
class _Resolved {
  const _Resolved({
    required this.text,
    required this.mode,
    this.barcode,
    this.product,
    this.problem,
  });

  final String text;
  final ScanInputMode mode;
  final String? barcode;
  final Product? product;
  final ScanLookupProblem? problem;
}
