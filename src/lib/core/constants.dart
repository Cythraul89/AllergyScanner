/// Application-wide constants that carry a documented requirement.
library;

/// Open Food Facts base URL. `world` serves all languages.
const String kOpenFoodFactsBaseUrl = 'https://world.openfoodfacts.org';

/// Open Food Facts requires a custom User-Agent identifying the app and a
/// contact address (`AppName/Version (contact)`).
///
/// MUST be replaced with a real, monitored address before the first release —
/// see doc/REQUIREMENTS.md §12 Q1. A placeholder violates their policy.
const String kOpenFoodFactsContact = 'allergyscanner@example.invalid';

/// Minimum interval between two product requests. Their documented limit is
/// 15 read requests per minute per IP; 4 s keeps us just inside it.
const Duration kOpenFoodFactsMinimumInterval = Duration(seconds: 4);

/// Remote product data older than this is stale (REQUIREMENTS R4.5). A row with
/// a manual override never becomes stale.
const Duration kProductCacheTtl = Duration(days: 30);

/// Scan history cap (REQUIREMENTS R4.8). The oldest entries are pruned on insert.
const int kMaxScanHistory = 500;

/// Prefix of an exported backup archive: `allergy_scanner_YYYYMMDD_HHmmss.zip`.
const String kBackupFilePrefix = 'allergy_scanner_';
