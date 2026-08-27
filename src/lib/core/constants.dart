/// Application-wide constants that carry a documented requirement.
library;

/// Open Food Facts base URL. `world` serves all languages.
const String kOpenFoodFactsBaseUrl = 'https://world.openfoodfacts.org';

/// Contact address the app identifies itself with to outbound services
/// (Open Food Facts' required User-Agent, MyMemory's optional `de` param).
///
/// MUST be replaced with a real, monitored address before the first release —
/// see doc/REQUIREMENTS.md §12 Q1. A placeholder violates Open Food Facts'
/// policy.
const String kAppContactEmail = 'allergyscanner@example.invalid';

/// Minimum interval between two product requests. Their documented limit is
/// 15 read requests per minute per IP; 4 s keeps us just inside it.
const Duration kOpenFoodFactsMinimumInterval = Duration(seconds: 4);

/// MyMemory translation API — keyless, used only to *suggest* a translated
/// allergen group name; every suggestion is reviewed before it becomes data.
const String kMyMemoryBaseUrl = 'https://api.mymemory.translated.net';

/// ISO 639-1 codes for the languages allergen-group name suggestions cover.
const List<String> kSupportedAllergenLanguages = <String>[
  'de',
  'en',
  'fr',
  'it',
];

/// Remote product data older than this is stale (REQUIREMENTS R4.5). A row with
/// a manual override never becomes stale.
const Duration kProductCacheTtl = Duration(days: 30);

/// Scan history cap (REQUIREMENTS R4.8). The oldest entries are pruned on insert.
const int kMaxScanHistory = 500;

/// Prefix of an exported backup archive: `allergy_scanner_YYYYMMDD_HHmmss.zip`.
const String kBackupFilePrefix = 'allergy_scanner_';
