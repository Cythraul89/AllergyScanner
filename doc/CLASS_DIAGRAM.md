# AllergyScanner — Provider Graph and Central Types

Companion to `doc/ARCHITECTURE.md`. This file shows who watches whom, and the
signatures of the types that carry the app's logic. It is generated from the
code by hand: when a signature changes, this file changes in the same commit.

State: matches the source as written. Nothing has been compiled, so the
signatures are the intent and the code — not a compiler's confirmation.

---

## 1. Provider graph

`■` = overridden in `main.dart` · `○` = read-side · `◆` = write-side (actions)

All of `■` and the DAO/read providers live in `lib/core/providers.dart`; the
`◆` providers live with their feature.

```
■ appDatabaseProvider ──────────┬─► ○ allergenTermDaoProvider
■ logServiceProvider            ├─► ○ productDaoProvider
■ dioProvider ──┬───────────────┼─► ○ scanDaoProvider
                │               └─► ○ settingsDaoProvider
■ appVersionProvider            │
■ openFoodFactsServiceProvider ─┘
■ textRecognitionServiceProvider
■ backupServiceProvider
■ webdavServiceProvider
■ secureStorageProvider
■ scanCapabilitiesProvider   (platform-derived default; overridden for one instance)

○ settingsProvider          StreamProvider<AppSettings>   ← settingsDao.watch()
   └─► ○ currentSettingsProvider   Provider<AppSettings>  (defaults while loading)
          └─► ○ themeModeProvider  Provider<ThemeMode>

○ allAllergenTermsProvider     StreamProvider<List<AllergenTerm>>
○ activeAllergenTermsProvider  StreamProvider<List<AllergenTerm>>
○ recentScansProvider          StreamProvider<List<Scan>>        (limit 3)
○ scanHistoryProvider          StreamProvider<List<Scan>>        ← historyFilterProvider
○ historyFilterProvider        StateProvider<ScanVerdict?>
○ scanResultProvider           StreamProvider.family<ScanResult?, String scanId>
○ productProvider              StreamProvider.family<Product?, String barcode>
○ routerProvider               Provider<GoRouter>   ← scanCapabilitiesProvider

◆ scanActionsProvider          Provider<ScanActions>
     uses: allergenTermDao, productDao, scanDao, settingsDao,
           openFoodFactsService, logService
◆ productActionsProvider       Provider<ProductActions>   → productDao, scanActions
◆ allergenTermActionsProvider  Provider<AllergenTermActions> → allergenTermDao
◆ historyActionsProvider       Provider<HistoryActions>   → scanDao
◆ backupActionsProvider        Provider<BackupActions>
     uses: backupService, webdavService, settingsDao, secureStorage, logService
```

Rules visible in the graph:

- Read and write are separate providers; widgets `ref.watch` the `○` side and
  `ref.read` the `◆` side.
- No `◆` provider is watched by another provider — actions are leaves. The one
  exception is deliberate: `productActionsProvider` composes
  `scanActionsProvider`, because correcting a product must re-run that scan.
- `scanActionsProvider` is the only place that combines terms, products and the
  matcher (ARCHITECTURE §4.1, §5.9).
- **Settings have no actions class**: writes go straight to
  `settingsDaoProvider`, whose setters are already column-scoped. A wrapper
  would only forward.
- The calculators (`TextNormalizer`, `AllergenMatcher`) have **no** providers.
  They are static, so they cannot acquire dependencies by accident.

### 1.1 Who watches what, per screen

| Screen | Watches | Reads |
|---|---|---|
| `DisclaimerScreen` | — | `settingsDaoProvider` |
| `AdaptiveShell` | `currentSettingsProvider` | — |
| `ScanScreen` | `scanCapabilitiesProvider`, `activeAllergenTermsProvider`, `recentScansProvider` | — |
| `BarcodeScanScreen` | — | `scanActionsProvider` |
| `TextCaptureScreen` | — | `textRecognitionServiceProvider` |
| `TextReviewScreen` | `scanCapabilitiesProvider` | `scanActionsProvider` |
| `ManualEntryScreen` | `scanCapabilitiesProvider` | `scanActionsProvider` |
| `ScanResultScreen` | `scanResultProvider(scanId)`, `scanCapabilitiesProvider` | `scanDaoProvider` (delete) |
| `ProductEditScreen` | `scanCapabilitiesProvider` | `productDaoProvider` (initial load), `productActionsProvider` |
| `AllergiesScreen` | `allAllergenTermsProvider` | `allergenTermActionsProvider` |
| `TermEditScreen` | — | `allergenTermDaoProvider` (initial load), `allergenTermActionsProvider` |
| `HistoryScreen` | `scanHistoryProvider`, `historyFilterProvider` | `historyActionsProvider` |
| `SettingsScreen` | `currentSettingsProvider` | `settingsDaoProvider` |
| `SyncScreen` | `currentSettingsProvider` | `settingsDaoProvider`, `backupActionsProvider` |
| `BackupScreen` | — | `backupActionsProvider` |
| `AboutScreen` | `appVersionProvider` | — |
| `LogsScreen` | — | `logServiceProvider` |

---

## 2. Central types

### 2.1 `TextNormalizer` — `core/calculators/text_normalizer.dart`

```dart
class TextNormalizer {
  const TextNormalizer._();

  /// Lowercase → fold Latin diacritics (and ß → ss) → non-letter/digit to
  /// space → collapse whitespace. REQUIREMENTS §5.2; the order matters.
  static String normalize(String input);

  static const int minimumTermLength = 3;
  static bool isSearchable(String normalizedTerm);
}
```

### 2.2 `AllergenMatcher` — `core/calculators/allergen_matcher.dart`

```dart
class AllergenMatcher {
  const AllergenMatcher._();

  static const int contextRadius = 24;

  /// Pure: no I/O, no logging, no clock. [text] is raw and normalised here.
  /// One match per term (its first occurrence), ordered by startOffset.
  static MatchOutcome match({
    required String text,
    required List<AllergenTerm> activeTerms,
  });

  /// Excerpt around a match in an already normalised text, with `…` where cut.
  static String contextFor(
    String normalizedText,
    int startOffset,
    int endOffset, {
    int radius = contextRadius,
  });
}

class MatchOutcome {
  final ScanVerdict verdict;
  final String normalizedText;      // what the offsets refer to
  final List<AllergenMatch> matches;
}

class AllergenMatch {
  final String termId;
  final String term;                // as the user typed it
  final String matchedText;
  final int startOffset;
  final int endOffset;              // exclusive

  String contextIn(String normalizedText, {int radius = AllergenMatcher.contextRadius});
}
```

### 2.3 `ScanCapabilities` — `core/utils/scan_capabilities.dart`

```dart
class ScanCapabilities {
  const ScanCapabilities({
    required this.canScanBarcode,
    required this.canRecognizeText,
  });
  const ScanCapabilities.none();
  factory ScanCapabilities.forCurrentPlatform();

  final bool canScanBarcode;
  final bool canRecognizeText;
  bool get isManualOnly;
}
```

### 2.4 `ScanActions` — `features/scan/scan_actions.dart`

```dart
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
  });

  /// The single pipeline (ARCHITECTURE §4.1): resolve → normalise → match →
  /// persist scan + matches in one transaction → prune history.
  Future<ScanOutcome> evaluate(ScanInput input);

  /// Same, for an existing scan id — used after a product correction.
  Future<ScanOutcome> reevaluate(String scanId);
}

class ScanOutcome {
  final String scanId;
  final ScanLookupProblem? lookupProblem;   // live scans only
}

enum ScanLookupProblem {
  productNotFound,
  serverUnreachable,
  lookupFailed,
  remoteLookupDisabled,
  noIngredientText,
}

sealed class ScanInput {}
class BarcodeInput extends ScanInput {
  final String barcode;
  final bool fromCamera;
  ScanInputMode get mode;            // barcode | manualBarcode
}
class TextInput extends ScanInput {
  final String text;
  final ScanInputMode mode;          // ocr | manualText
}
```

### 2.5 `OpenFoodFactsService` — `core/services/open_food_facts_service.dart`

```dart
class OpenFoodFactsService {
  OpenFoodFactsService({
    required Dio dio,
    required LogService log,
    String baseUrl = kOpenFoodFactsBaseUrl,
    Duration minimumInterval = kOpenFoodFactsMinimumInterval,
    DateTime Function()? now,
  });

  /// Never throws. Spaces requests by [minimumInterval]; every error is logged
  /// and mapped by _mapDioError.
  Future<OffResult> fetchProduct(String barcode, {required String preferredLanguage});
}

sealed class OffResult {}
final class OffSuccess   extends OffResult { final Product product; }
final class OffNotFound  extends OffResult {}   // server: no such barcode
final class OffTransient  extends OffResult {}  // offline, timeout, 5xx, 429
final class OffFailure   extends OffResult { final String message; }
```

`OffNotFound` and `OffTransient` are distinct by design — ARCHITECTURE §5.7.

### 2.6 `TextRecognitionService` — `core/services/text_recognition_service.dart`

```dart
abstract interface class TextRecognitionService {
  /// Recognised text, or '' when nothing was found. Deletes the file first.
  Future<String> recognizeFile(String imagePath);
  Future<void> dispose();
}

class MlKitTextRecognitionService implements TextRecognitionService { … }   // Android/iOS
class UnsupportedTextRecognitionService implements TextRecognitionService { … }
```

### 2.7 `BackupService` and `WebdavService`

```dart
class BackupService {
  BackupService({required AppDatabase database, required LogService log, DateTime Function()? now});

  static const int backupFormatVersion = 1;
  static String archiveFileName(DateTime at);   // allergy_scanner_YYYYMMDD_HHmmss.zip

  Future<List<int>> exportToBytes();            // testable without path_provider
  Future<File> exportToFile();
  Future<ImportOutcome> importFromFile(File file);
  Future<ImportOutcome> importFromBytes(List<int> bytes);  // throws BackupFormatException
}

class ImportOutcome { final int imported; final int skipped; bool get hasSkipped; }

class WebdavService {
  WebdavService({required LogService log, WebdavClientFactory? clientFactory});

  Future<WebdavOutcome> testConnection(WebdavCredentials credentials);
  Future<WebdavOutcome> uploadBackup(WebdavCredentials credentials, File archive);
  Future<WebdavOutcome> findLatestBackupName(WebdavCredentials credentials);
  Future<WebdavOutcome> downloadBackup(WebdavCredentials credentials, String name);
}

sealed class WebdavOutcome {}
final class WebdavSuccess<T>              extends WebdavOutcome { final T? value; }
final class WebdavUntrustedCertificate    extends WebdavOutcome { final String observedFingerprint; }
final class WebdavAuthenticationFailed    extends WebdavOutcome {}
final class WebdavTransient               extends WebdavOutcome {}
final class WebdavFailure                 extends WebdavOutcome { final String message; }
```

### 2.8 Domain models — `core/models/`

```dart
class AllergenTerm {                  // Equatable, const, copyWith
  final String id, term, normalizedTerm;
  final bool isActive;
  final String? note;
  final DateTime createdAt, updatedAt;
}

class Product {
  final String barcode;
  final String? productName, brands, quantity, ingredientsText,
                ingredientsLanguage, imageUrl;
  final List<String> allergensTags, tracesTags;
  final ProductSource source;
  final bool hasManualOverride;
  final DateTime? fetchedAt;
  final DateTime updatedAt;

  bool get hasIngredients;
  bool isStale(DateTime now);          // always false when hasManualOverride
  String get displayName;
}

class Scan {
  final String id;
  final DateTime scannedAt;
  final ScanInputMode inputMode;
  final String? barcode, productNameSnapshot;
  final String evaluatedText;
  final ScanVerdict verdict;
  final int matchCount;
  bool get isBarcodeScan;
}

class ScanResult {
  final Scan scan;
  final List<ScanMatch> matches;
  final Product? product;              // null for text scans
}

class ScanMatch {
  final String id, scanId;
  final String? allergenTermId;        // null once the term was deleted
  final String termSnapshot, matchedText;
  final int startOffset, endOffset;
}

class AppSettings {
  final ThemeMode themeMode;                       // default system
  final String preferredIngredientsLanguage;       // default 'en'
  final bool remoteLookupEnabled;                  // default true
  final DateTime? disclaimerAcknowledgedAt, lastSyncAt;
  final String? webdavBaseUrl, webdavUsername, certificateFingerprint;
  bool get disclaimerAcknowledged;
  bool get isSyncConfigured;
}

enum ScanVerdict    { hit, noMatch, unknown }
enum ScanInputMode  { barcode, ocr, manualText, manualBarcode }
enum ProductSource  { openFoodFacts, manual }
```

### 2.9 DAO surface — `core/database/daos/`

```dart
class AllergenTermDao {
  Stream<List<AllergenTerm>> watchAll();        // active first, then alphabetical
  Stream<List<AllergenTerm>> watchActive();
  Future<List<AllergenTerm>> getActive();
  Future<AllergenTerm?> findById(String id);
  Future<AllergenTerm?> findByNormalizedTerm(String normalizedTerm);
  Future<void> insertTerm(AllergenTerm term);
  Future<void> updateTerm({
    required String id, required String term,
    required String normalizedTerm, required DateTime updatedAt, String? note,
  });
  Future<void> setActive({required String id, required bool isActive, required DateTime updatedAt});
  Future<void> deleteById(String id);
}

class ProductDao {
  Stream<Product?> watchByBarcode(String barcode);
  Future<Product?> findByBarcode(String barcode);
  Future<bool> upsertFromRemote(Product product);   // false = manual override kept
  Future<void> saveManualOverride(Product product);
  Future<void> deleteByBarcode(String barcode);
  Future<List<Product>> getAll();
  static Product toModel(ProductRow row);
}

class ScanDao {
  Stream<List<Scan>> watchRecent({int limit = 3});
  Stream<List<Scan>> watchHistory({ScanVerdict? verdict});
  Stream<ScanResult?> watchResult(String scanId);   // one left-joined query
  Future<ScanResult?> findResult(String scanId);
  Future<String> insertWithMatches({
    required Scan scan, required List<ScanMatch> matches, int historyLimit = 500,
  });                                              // one transaction, then prune
  Future<void> deleteById(String id);
  Future<void> deleteAll();
  Future<List<Scan>> getAll();
  Future<List<ScanMatch>> getAllMatches();
}

class SettingsDao {
  Stream<AppSettings> watch();      // defaults while the row is absent
  Future<AppSettings> get();        // never writes
  Future<void> ensureDefaults({required String deviceLanguage});
  Future<void> setThemeMode(ThemeMode mode);
  Future<void> setRemoteLookupEnabled(bool enabled);
  Future<void> setPreferredLanguage(String language);
  Future<void> acknowledgeDisclaimer(DateTime at);
  Future<void> setWebdav({String? baseUrl, String? username, String? certificateFingerprint});
  Future<void> setLastSyncAt(DateTime? at);
}
```

Every mutation is column-scoped; no DAO takes a whole settings object.

---

## 3. Navigation tree

```dart
MaterialApp.router(routerConfig: ref.watch(routerProvider))
└── GoRouter(initialLocation: '/scan')
    └── StatefulShellRoute.indexedStack → AdaptiveShell
        │     ├── DisclaimerScreen        while not acknowledged (gate, §5.13)
        │     ├── MobileShell   (< 600 dp)
        │     └── DesktopShell  (>= 600 dp, extended > 1200)
        ├── branch 0 → /scan
        │              ├── /scan/barcode          only if canScanBarcode
        │              ├── /scan/text             only if canRecognizeText
        │              ├── /scan/review           extra: recognised text
        │              ├── /scan/manual
        │              └── /scan/result/:scanId   extra: ScanLookupProblem?
        │                  └── product            extra: barcode
        ├── branch 1 → /allergies
        │              ├── /allergies/add
        │              └── /allergies/:termId/edit
        ├── branch 2 → /history
        │              └── /history/:scanId       ScanResultScreen (same widget)
        └── branch 3 → /settings
                       ├── backup, sync, about, privacy, logs
```

`ScanResultScreen(scanId)` is the widget behind both `/scan/result/:scanId` and
`/history/:scanId` — ARCHITECTURE §5.11. Tapping the current tab resets its
branch to the root (`goToBranch` in `adaptive_shell.dart`).
