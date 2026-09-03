# AllergyScanner — Provider Graph and Central Types

Companion to `doc/ARCHITECTURE.md`. This file shows who watches whom, and the
signatures of the types that carry the app's logic. It is generated from the
code by hand: when a signature changes, this file changes in the same commit.

State: matches the source as written and compiled — `flutter analyze
--fatal-infos` and `flutter test` pass as of 2026-09-03 (see CLAUDE.md
"Current state"), though only on the Flutter/Dart host toolchain; no native
Android/iOS device build has run yet.

---

## 1. Provider graph

`■` = overridden in `main.dart` · `○` = read-side · `◆` = write-side (actions)

All of `■` and the DAO/read providers live in `lib/core/providers.dart`; the
`◆` providers live with their feature.

```
■ appDatabaseProvider ──────────┬─► ○ allergenTermDaoProvider
■ logServiceProvider            ├─► ○ allergenGroupDaoProvider
■ dioProvider ──┬───────────────┼─► ○ productDaoProvider
                │               ├─► ○ scanDaoProvider
■ appVersionProvider            └─► ○ settingsDaoProvider
■ openFoodFactsServiceProvider ─┤
■ translationServiceProvider ───┘
■ textRecognitionServiceProvider
■ backupServiceProvider
■ scanPhotoServiceProvider
■ webdavServiceProvider
■ secureStorageProvider
■ scanCapabilitiesProvider   (platform-derived default; overridden for one instance)

○ settingsProvider          StreamProvider<AppSettings>   ← settingsDao.watch()
   └─► ○ currentSettingsProvider   Provider<AppSettings>  (defaults while loading)
          ├─► ○ themeModeProvider  Provider<ThemeMode>
          └─► ○ appLocaleProvider  Provider<Locale?>  (null → MaterialApp follows the system locale)

○ allAllergenTermsProvider     StreamProvider<List<AllergenTerm>>
○ activeAllergenTermsProvider  StreamProvider<List<AllergenTerm>>
○ allAllergenGroupsProvider    StreamProvider<List<AllergenGroupWithTerms>>  (features/allergies)
○ ungroupedAllergenTermsProvider  StreamProvider<List<AllergenTerm>>  (features/allergies)
○ recentScansProvider          StreamProvider<List<Scan>>        (limit 3)
○ scanHistoryProvider          StreamProvider<List<Scan>>        ← historyFilterProvider
○ historyFilterProvider        StateProvider<ScanVerdict?>
○ scanResultProvider           StreamProvider.family<ScanResult?, String scanId>
○ productProvider              StreamProvider.family<Product?, String barcode>
○ routerProvider               Provider<GoRouter>   ← scanCapabilitiesProvider

◆ scanActionsProvider          Provider<ScanActions>
     uses: allergenTermDao, productDao, scanDao, settingsDao,
           openFoodFactsService, logService, scanPhotoService
◆ productActionsProvider       Provider<ProductActions>   → productDao, scanActions
◆ scanDetailsActionsProvider   Provider<ScanDetailsActions>  → scanDao, scanPhotoService
◆ allergenTermActionsProvider  Provider<AllergenTermActions> → allergenTermDao
◆ allergenGroupActionsProvider Provider<AllergenGroupActions> → allergenGroupDao  (features/allergies)
◆ translationSuggestionsProvider  Provider<TranslationSuggestionService> → translationService  (features/allergies)
◆ historyActionsProvider       Provider<HistoryActions>   → scanDao, scanPhotoService
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
| `AllergyScannerApp` | `themeModeProvider`, `appLocaleProvider`, `routerProvider` | — |
| `DisclaimerScreen` | — | `settingsDaoProvider` |
| `AdaptiveShell` | `currentSettingsProvider` | — |
| `ScanScreen` | `scanCapabilitiesProvider`, `activeAllergenTermsProvider`, `recentScansProvider` | — |
| `BarcodeScanScreen` | — | `scanActionsProvider` |
| `TextCaptureScreen` | — | `textRecognitionServiceProvider` |
| `TextReviewScreen` | `scanCapabilitiesProvider`, `activeAllergenTermsProvider` | `scanActionsProvider` |
| `ManualEntryScreen` | `scanCapabilitiesProvider` | `scanActionsProvider` |
| `ScanResultScreen` | `scanResultProvider(scanId)`, `scanCapabilitiesProvider`, `allAllergenTermsProvider` (match-group bucketing) | `historyActionsProvider` (delete), `scanPhotoServiceProvider` (thumbnail) |
| `ProductEditScreen` | `scanCapabilitiesProvider` | `productDaoProvider` (initial load), `productActionsProvider` |
| `ScanDetailsEditScreen` | — | `scanDaoProvider` (initial load), `scanDetailsActionsProvider`, `scanPhotoServiceProvider` |
| `AllergiesScreen` | `allAllergenGroupsProvider`, `ungroupedAllergenTermsProvider` | `allergenTermActionsProvider` |
| `TermEditScreen` | — | `allergenTermDaoProvider` (initial load), `allergenTermActionsProvider` |
| `GroupEditScreen` | `allAllergenGroupsProvider`, `ungroupedAllergenTermsProvider`, `currentSettingsProvider` | `allergenGroupDaoProvider` (initial load), `allergenGroupActionsProvider`, `allergenTermActionsProvider`, `translationSuggestionsProvider` |
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

### 2.1a `SpellingVariant` — `core/calculators/spelling_variant.dart`

```dart
class SpellingVariant {
  const SpellingVariant._();

  /// ö→oe, ä→ae, ü→ue, ß→ss (case-preserving); null if none apply.
  /// Used by AllergenMatcher as a search-time fallback (§2.2) —
  /// TextNormalizer's own folding (ö→o) is unchanged.
  static String? asciiAlternative(String term);
}
```

### 2.2 `AllergenMatcher` — `core/calculators/allergen_matcher.dart`

```dart
class AllergenMatcher {
  const AllergenMatcher._();

  static const int contextRadius = 24;

  /// Pure: no I/O, no logging, no clock. [text] is raw and normalised here.
  /// One match per term (its first occurrence), ordered by startOffset. If a
  /// term does not match directly, SpellingVariant's ASCII-substitute
  /// spelling is tried as a fallback (§2.1a, REQUIREMENTS R5.3a).
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
    required ScanPhotoService scanPhotos,
    Uuid uuid = const Uuid(),
    DateTime Function()? now,
  });

  /// The single pipeline (ARCHITECTURE §4.1): resolve → normalise → match →
  /// persist scan + matches in one transaction → prune history (deleting any
  /// pruned rows' photo files via [scanPhotos]).
  Future<ScanOutcome> evaluate(ScanInput input);

  /// Same, for an existing scan id — used after a product correction.
  /// Carries the existing row's name/shop/photoPath forward (ARCHITECTURE
  /// §5.16) — this is the fix for the bug the history-details feature found:
  /// `ScanDao.insertWithMatches`'s `insertOnConflictUpdate` overwrites every
  /// column it is given a value for.
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

### 2.4a `IngredientMarkerDetector` — `core/calculators/ingredient_marker_detector.dart`

```dart
class IngredientMarkerDetector {
  /// Scans raw (unnormalised) text for a localised "Ingredients:" header —
  /// English, German, French (accent optional), Italian. Colon required
  /// (REQUIREMENTS R5.8). Pure, no I/O.
  static MarkerDetectionResult detect(String rawText);
}

sealed class MarkerDetectionResult {}
final class MarkerFound extends MarkerDetectionResult {
  final String matchedMarker;   // literal text as found, e.g. "Zutaten:"
  final String sectionText;     // marker end → end of text, left-trimmed
}
final class MarkerNotFound extends MarkerDetectionResult {}
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

### 2.5a `TranslationService` — `core/services/translation_service.dart`

```dart
class TranslationService {
  TranslationService({
    required Dio dio,
    required LogService log,
    String baseUrl = kMyMemoryBaseUrl,
    String? contactEmail = kAppContactEmail,
  });

  /// Never throws. Not throttled (unlike OpenFoodFactsService — this is
  /// called rarely, on an explicit "Suggest translations" tap, not on
  /// every scan). [sourceLanguage]/[targetLanguage] are ISO 639-1 codes.
  Future<TranslationResult> translate({
    required String text,
    required String sourceLanguage,
    required String targetLanguage,
  });
}

sealed class TranslationResult {}
final class TranslationSuccess extends TranslationResult {
  final String translatedText;
  final double? quality;   // best-effort, never gates acceptance
}
final class TranslationNotFound extends TranslationResult {}   // rarely returned by MyMemory in practice
final class TranslationTransient extends TranslationResult {}  // quota exhausted, 5xx, unreachable
final class TranslationFailure extends TranslationResult { final String message; }
```

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

### 2.7 `BackupService`, `ScanPhotoService` and `WebdavService`

```dart
class BackupService {
  BackupService({
    required AppDatabase database,
    required LogService log,
    required ScanPhotoService scanPhotos,
    DateTime Function()? now,
  });

  /// v2: scans gained name/shop/photoPath, and one raw-bytes archive entry
  /// per attached photo (named after its own photoPath, not base64-in-JSON).
  /// A v1 archive still imports — those fields are simply absent.
  static const int backupFormatVersion = 2;
  static String archiveFileName(DateTime at);   // allergy_scanner_YYYYMMDD_HHmmss.zip

  Future<List<int>> exportToBytes();            // testable without path_provider
  Future<File> exportToFile();
  Future<ImportOutcome> importFromFile(File file);
  Future<ImportOutcome> importFromBytes(List<int> bytes);  // throws BackupFormatException
}

class ImportOutcome { final int imported; final int skipped; bool get hasSkipped; }

/// Carries a structured reason, not a hardcoded message — BackupService has
/// no BuildContext to localise with; the caller maps `problem` to a string
/// (ARCHITECTURE §5.17), the same pattern as ScanLookupProblem.
class BackupFormatException implements Exception { final BackupFormatProblem problem; }
sealed class BackupFormatProblem {}
final class ArchiveUnreadable      extends BackupFormatProblem {}
final class ArchiveMissingData     extends BackupFormatProblem {}
final class ArchiveContentInvalid  extends BackupFormatProblem {}
final class ArchiveSchemaTooNew    extends BackupFormatProblem { final int archiveSchemaVersion; final int appSchemaVersion; }
final class ArchiveFormatTooNew    extends BackupFormatProblem { final int archiveFormatVersion; final int appFormatVersion; }

class ScanPhotoService {
  ScanPhotoService(Directory directory, {required LogService log});
  static Future<ScanPhotoService> open({required LogService log});  // <documents>/scan_photos

  /// Copies the source file in, keyed by scanId; returns the path to store
  /// in scans.photoPath.
  Future<String> attach({required String scanId, required String sourcePath});
  /// Keyed by photoPath's basename within this service's own directory —
  /// not by calling getApplicationDocumentsDirectory() again, so this is
  /// correct however the service was constructed (ARCHITECTURE §5.16).
  Future<File> resolve(String photoPath);
  Future<void> restoreFromBytes({required String photoPath, required List<int> bytes});  // backup import
  Future<void> delete(String photoPath);       // best-effort, log-and-swallow
  Future<void> deleteMany(Iterable<String> photoPaths);
}

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
  final String? groupId;              // null = ungrouped; set via setGroup, not copyWith
  final DateTime createdAt, updatedAt;
}

class AllergenGroup {                 // Equatable, const
  final String id, label;
  final DateTime createdAt, updatedAt;
}

class AllergenGroupWithTerms {        // in-memory composite, never persisted
  final AllergenGroup group;
  final List<AllergenTerm> terms;
  bool get isActive;                  // true iff every member is active (R4.1d)
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
  final String? name, shop, photoPath;  // set after the fact via Edit details
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
  final String? appLanguage;                       // null = follow system (R7.15)
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
  Stream<List<AllergenTerm>> watchUngrouped();
  Future<void> setGroup({required String id, required String? groupId, required DateTime updatedAt});
  Future<void> setActiveForGroup({required String groupId, required bool isActive, required DateTime updatedAt});
  static AllergenTerm toModel(AllergenTermRow row);   // public: reused by AllergenGroupDao
}

class AllergenGroupDao {
  /// One left-joined query — every group and its members in one stream
  /// event, same reasoning as ScanDao.watchResult.
  Stream<List<AllergenGroupWithTerms>> watchAllWithTerms();
  Future<AllergenGroup?> findById(String id);
  Future<void> insertGroup(AllergenGroup group);
  Future<void> updateLabel({required String id, required String label, required DateTime updatedAt});
  Future<void> deleteById(String id);   // members survive, ungrouped (FK setNull)
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
  /// One transaction, then prune. Returns the pruned rows' photo paths —
  /// ScanDao stays DB-only, the caller owns file deletion (ARCHITECTURE §5.16).
  Future<({String scanId, List<String> prunedPhotoPaths})> insertWithMatches({
    required Scan scan, required List<ScanMatch> matches, int historyLimit = 500,
  });
  /// Column-scoped: touches only name/shop/photoPath, never evaluatedText or
  /// verdict.
  Future<void> updateDetails({
    required String scanId,
    Value<String?> name, Value<String?> shop, Value<String?> photoPath,
  });
  Future<Scan?> deleteById(String id);    // returns the deleted row, or null
  Future<List<Scan>> deleteAll();         // returns every deleted row
  Future<List<Scan>> getAll();
  Future<List<ScanMatch>> getAllMatches();
}

class SettingsDao {
  Stream<AppSettings> watch();      // defaults while the row is absent
  Future<AppSettings> get();        // never writes
  Future<void> ensureDefaults({required String deviceLanguage});
  Future<void> setThemeMode(ThemeMode mode);
  Future<void> setAppLanguage(String? language);   // null reverts to following the system
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
        │                  ├── product            extra: barcode
        │                  └── details            name/shop/photo (§5.16)
        ├── branch 1 → /allergies
        │              ├── /allergies/:termId/edit   existing term only
        │              ├── /allergies/groups/add
        │              └── /allergies/groups/:groupId/edit
        ├── branch 2 → /history
        │              └── /history/:scanId       ScanResultScreen (same widget)
        └── branch 3 → /settings
                       ├── backup, sync, about, privacy, logs
```

`ScanResultScreen(scanId)` is the widget behind both `/scan/result/:scanId` and
`/history/:scanId` — ARCHITECTURE §5.11. Tapping the current tab resets its
branch to the root (`goToBranch` in `adaptive_shell.dart`).
