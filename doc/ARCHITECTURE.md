# AllergyScanner — Architecture

Companion to `doc/REQUIREMENTS.md` (what the app must do) and
`doc/SCREENS.md` (how it presents itself). This document fixes *how* it is
built. Section 5 is append-only: every real decision, its reason, and the
alternative that was rejected.

---

## 1. Technology stack

| Concern | Library | Note |
|---|---|---|
| UI | Flutter, Material 3 | Indigo seed, light + dark, `themeMode` from settings |
| State | `flutter_riverpod` (Riverpod 2, manual providers) | No code generation |
| Navigation | `go_router`, `StatefulShellRoute.indexedStack` | Per-tab state survives switching |
| Persistence | `drift` + `drift_flutter` + `path_provider` + `path` | One DB file in the app documents dir |
| HTTP | `dio` | One shared instance, timeouts always set |
| Barcode scanning | `mobile_scanner` | Requires Dart `^3.7.0` / Flutter ≥ 3.29 |
| Text recognition | `google_mlkit_text_recognition` | Android, iOS only, fully on-device |
| Photo capture / pick | `image_picker` | System camera UI; no in-app preview (§5.4) |
| Secrets | `flutter_secure_storage` | WebDAV password only |
| Backup | `archive`, `file_picker`, `share_plus` | ZIP export/import |
| App version | `package_info_plus` | About screen |
| Links | `url_launcher` | Privacy, licence, Open Food Facts attribution |
| Utilities | `uuid`, `intl`, `crypto`, `equatable` | `crypto` for the certificate fingerprint |
| Lints | `flutter_lints` + the house `analysis_options.yaml` | `--fatal-infos` is the gate |
| Codegen | `drift_dev`, `build_runner` | `*.g.dart` not committed |

Not used, deliberately:

- **`sqlite3_flutter_libs`** — end-of-life as of `0.6.0+eol`; from
  `package:sqlite3` 3.x it does nothing. `drift_flutter` is drift's current
  documented setup and replaces both it and the hand-written
  `NativeDatabase(file)` opener. See decision §5.12.
- **`decimal`** — this app has no monetary or exact-decimal arithmetic.
- **`workmanager` / `flutter_local_notifications`** — nothing is
  time-triggered [REQUIREMENTS §1.2].
- **`fl_chart`** — no charts.
- **`permission_handler`** — `mobile_scanner` and `image_picker` request the
  camera permission themselves; a second permission stack would only add a
  divergent code path.

Every version in `src/pubspec.yaml` was read from pub.dev on 2026-08-20 and
none has been resolved by `flutter pub get` yet. Two constraints follow from
the plugins rather than from the house style:

- `mobile_scanner` 7.4.0 requires `sdk: ^3.7.0` and Flutter ≥ 3.29, so the
  house-style `>=3.3.0 <4.0.0` is not satisfiable.
- `google_mlkit_text_recognition` 0.17.1 requires `minSdkVersion 21` and iOS
  deployment target 15.5; both are patched into the generated platform folders
  by `build.yml`.
- `flutter_riverpod` is pinned to `^2.6.1` per the house style although 3.4.2
  exists. Riverpod 3 moves `StateProvider` to a legacy import, so migrating is
  a deliberate change, not a version bump.

---

## 2. Project structure

```
src/lib/
├── main.dart                       bootstrap: logger, DB, Dio, services, overrides
├── app.dart                        MaterialApp.router, themes, routerProvider
├── core/
│   ├── constants.dart              Open Food Facts contact/limits, TTL, history cap
│   ├── providers.dart              overridden singletons, DAO + read providers
│   ├── database/
│   │   ├── app_database.dart       @DriftDatabase, schemaVersion, migrations
│   │   ├── tables/                 allergen_terms, products, scans,
│   │   │                           scan_matches, settings
│   │   └── daos/                   allergen_term, product, scan, settings
│   ├── models/
│   │   ├── allergen_term.dart
│   │   ├── product.dart
│   │   ├── scan.dart               Scan + ScanMatch + ScanResult
│   │   ├── scan_input.dart         sealed: BarcodeInput | TextInput
│   │   ├── enums.dart              ScanVerdict, ScanInputMode, ProductSource
│   │   └── app_settings.dart
│   ├── calculators/
│   │   ├── text_normalizer.dart    the single normalisation function (§5.1)
│   │   └── allergen_matcher.dart   pure matching + verdict + match context
│   ├── services/
│   │   ├── log_service.dart        file logger, everything logs through it
│   │   ├── open_food_facts_service.dart   Dio client + sealed OffResult
│   │   ├── text_recognition_service.dart  ML Kit behind an interface
│   │   ├── backup_service.dart     ZIP export/import (bytes and file)
│   │   └── webdav_service.dart     Nextcloud sync + certificate pinning
│   ├── utils/
│   │   ├── scan_capabilities.dart  the only place that asks about the platform
│   │   ├── formatters.dart         dates, verdict wording
│   │   └── app_version.dart
│   └── widgets/
│       ├── error_view.dart
│       ├── empty_view.dart
│       └── verdict_banner.dart     banner + badge, shared by result and history
├── features/
│   ├── disclaimer/                 the gate shown before the shell (§5.13)
│   ├── scan/                       hub, camera, capture, review, manual,
│   │                               scan_actions.dart (the pipeline)
│   ├── result/                     result view + product correction
│   ├── allergies/                  list + add/edit screen + actions
│   ├── history/                    list + filter + actions
│   └── settings/                   settings, about, privacy, logs, backup, sync
└── shell/
    ├── adaptive_shell.dart         kDesktopBreakpoint = 600, disclaimer gate
    ├── mobile_shell.dart           NavigationBar
    └── desktop_shell.dart          NavigationRail (extended > ~1200)
```

`core/` never imports from `features/`. Imports inside `lib/` are relative.

---

## 3. Data model

Tables, columns and constraints are specified in `doc/REQUIREMENTS.md` §4 and
are not duplicated here. Structural facts:

```
allergen_terms ──┐ (setNull)
                 ├──< scan_matches >──── scans ──── products
products ────────┘ (cascade from scans)   (setNull)
settings (single row, id = 1)
```

- `schemaVersion` starts at 1. Every change bumps it and adds an
  `if (from < N)` step in `onUpgrade`.
- Foreign keys are chosen so history stays readable: `scan_matches.scanId`
  cascades, `scan_matches.allergenTermId` and `scans.barcode` are nullable and
  `setNull` (§5.5).
- Row classes are `@DataClassName('<Name>Row')` and are mapped to the
  immutable domain models in the DAO layer; nothing above the DAO sees a Drift
  type.

---

## 4. Layered architecture

```
UI          features/**  — ConsumerWidget screens, layout and user intent only
   │ watches / reads
State       *_provider.dart — Riverpod providers; read side and write side split
   │ calls
Data        DAOs (watch* streams, targeted writes)
            Services (Open Food Facts, ML Kit, backup, WebDAV, log)
   │ persists
Storage     SQLite via Drift/NativeDatabase, app documents dir,
            WebDAV password in flutter_secure_storage

Pure        core/calculators/** — text normalisation + matching, no I/O,
                                 unit-tested rule by rule
```

Rules that keep it honest:

- A screen never normalises text, never matches, never opens the DB.
- A provider never builds widgets and never shows dialogs or snackbars.
- A service never reads a provider; it is constructed with what it needs.
- The matcher takes models in and returns a result out — it cannot log, fetch
  or persist.

### 4.1 The scan pipeline

The one flow worth drawing, because every screen in `doc/SCREENS.md` is a step
in it:

```
ScanInput (barcode | text)
   │
   ├─ BarcodeInput ─► ProductDao.findByBarcode
   │                      hit  ────────────────────────────┐
   │                      miss + remoteLookupEnabled       │
   │                        └► OpenFoodFactsService         │
   │                             OffSuccess ─► ProductDao.upsert ─┤
   │                             OffNotFound ─────► verdict unknown
   │                             OffTransient ────► verdict unknown + retry
   │                                                       │
   └─ TextInput ───────────────────────────────────────────┤
                                                           ▼
                                          evaluatedText + active terms
                                                           │
                                       TextNormalizer ──► AllergenMatcher
                                                           │
                                          ScanResult (verdict, matches)
                                                           │
                                       ScanDao.insertWithMatches (transaction)
                                                           │
                                                  Result view (§7)
```

- The pipeline lives in one place (`features/scan/scan_actions.dart`, exposed
  as `scanActionsProvider`), so barcode, OCR and manual entry cannot drift
  apart in how they evaluate or persist.
- Persisting happens **before** the result view is shown [R7.7], inside one
  transaction together with its matches.

---

## 5. Key design decisions

### 5.1 One normalisation function, used by matcher and uniqueness check

Normalisation (`core/calculators/text_normalizer.dart`) is a single pure
function. The matcher, the duplicate check when adding a term and the stored
`normalizedTerm` column all call it.

*Why:* if the term is normalised differently from the ingredient text, terms
silently stop matching — the worst possible failure for this app, because it
looks like "no allergen found". One function makes that class of bug
impossible.

*Rejected:* normalising inline where needed (two implementations that drift),
and normalising only at match time (then the uniqueness check in §4.1 cannot
work and every match re-normalises every term).

### 5.2 `normalizedTerm` is stored, not computed on read

*Why:* it is the column the uniqueness constraint sits on, and the matcher
runs it against every scan; recomputing per scan is wasted work with no
benefit.

*Consequence:* it must be rewritten whenever `term` changes [R4.3], and a
change to the normalisation rules is a **migration** — the `onUpgrade` step has
to recompute the column for all rows. This is written down because forgetting
it would silently break matching for existing terms.

*Rejected:* a Drift generated/virtual column — the folding rules in §5.2 of the
requirements (NFKD, `ß` → `ss`) are not expressible in SQLite without an
application-defined function, which would have to be registered identically in
every DB opening path including the test one.

### 5.3 Plain substring matching, no alias dictionary (v0.1)

*Why:* explicit user decision; it keeps the matcher trivially testable and
avoids shipping a curated allergen vocabulary whose incompleteness would itself
create false confidence.

*Consequences accepted:* false negatives for Latin names, E-numbers and
translations; false positives inside longer words. Mitigations are product
requirements, not code hacks: a minimum term length of 3, match context shown
in the result, and wording that never says "safe" [REQUIREMENTS §5.4–5.6].

*Rejected for now:* alias lists per term (planned feature 1), word-boundary
matching (planned feature 2 — it would *lose* true positives such as
`milk` inside `buttermilk`, so it must be an option, not a default),
stemming and fuzzy/Levenshtein matching (false positives on an allergy app are
not a neutral trade).

### 5.4 Photo capture instead of a live camera preview for OCR

OCR takes a still photo through `image_picker` (system camera UI) and runs ML
Kit on the file.

*Why:* a live preview means the `camera` plugin, an image stream, per-platform
`InputImage` conversion with rotation/format handling, and lifecycle
management of the controller — a large amount of fragile code for a task the
user performs once per product and where a sharp still photo recognises
*better* than a streamed frame. The user can also pick an existing image,
which falls out for free.

*Rejected:* `camera` + `InputImage.fromBytes` streaming (revisit only if
users report that framing the list is hard), and `mobile_scanner`'s image
analysis (it detects barcodes, not text).

### 5.5 History rows are self-contained snapshots

`scans` stores `evaluatedText` and `productNameSnapshot`; `scan_matches`
stores `termSnapshot`. Foreign keys to `products` and `allergen_terms` are
nullable with `setNull`.

*Why:* the history is a record of what the user was told at that moment.
Deleting an allergy term or correcting a product must not retroactively change
or destroy a past verdict, and re-opening a scan must work offline [R4.7].

*Rejected:* recomputing the verdict when a history entry is opened (the entry
would change under the user and would need the network), and `restrict` FKs
(the user could no longer delete a term that was ever matched).

### 5.6 Manual product overrides win over remote data, permanently

`hasManualOverride = true` makes a row immune to fetch overwrites and to the
30-day staleness rule [R4.4, R4.5].

*Why:* the user corrected it by reading the physical package — that is the best
data the app will ever have. Open Food Facts is crowd-sourced and may be wrong
or localised differently.

*Rejected:* a "remote wins after N days" rule (silently reverts a correction
the user made for a reason), and merging field by field (unexplainable to the
user in a result view).

### 5.7 `OffNotFound` and `OffTransient` are distinct results

The Open Food Facts service returns a sealed result; "server said no such
product" and "we could not reach the server" never share a code path [R6.1].

*Why:* collapsing them turns an outage or a flight-mode phone into "this
product contains nothing from your list is unknown" with no way to tell that a
retry would help. Both currently render as `unknown`, but with different text
and different next actions — and the distinction is in the type, so a future
caller cannot lose it.

*Rejected:* returning `Product?` (the classic `results?.firstOrNull` shape),
and throwing exceptions for the not-found case (not exceptional).

### 5.8 Platform capability lives in one value

`core/utils/scan_capabilities.dart` exposes `canScanBarcode` and
`canRecognizeText`, derived once from `Platform.*`.

*Why:* three plugins with three different platform matrices
(`mobile_scanner`: Android/iOS/macOS, ML Kit: Android/iOS, `image_picker`
camera source: mobile) would otherwise produce `Platform.isAndroid ||
Platform.isIOS` checks scattered through the widget tree, and each new plugin
version silently invalidates some of them. `routerProvider` watches it, so a
route for an unavailable feature is **not registered at all** and no navigation
path can reach a dead screen [R3.1, R3.2].

Since v0.1 targets Android and iOS only, both flags are currently always true
in production. The indirection stays: it is what keeps R3.1 enforceable when a
platform is added back, and `ScanCapabilities.none()` is how the widget test
exercises the manual-only layout without faking a platform.

*Rejected:* try-and-catch-`MissingPluginException` at use time (the user has
already tapped a button that cannot work), and a compile-time flag per platform
build (the same binary shape must serve all).

### 5.9 The scan pipeline exists exactly once

See §4.1. Barcode, OCR and manual input all produce a `ScanInput` and enter the
same evaluate-and-persist function.

*Why:* three entry points × (normalise, match, verdict, persist, prune) is
where "the manual path forgot to write history" bugs come from.

### 5.10 No background work, no notifications

*Why:* nothing in this app is time-triggered — a scan is always user-initiated.
This also removes the whole `workmanager` trap surface (isolate DB opening,
`@pragma('vm:entry-point')`, Android-only initialisation).

*Consequence:* WebDAV sync happens on app start and on demand only, never
scheduled.

### 5.11 The result view is one widget, reached from two shell branches

`features/result/` owns a `ScanResultView` that takes a `scanId`. It is routed
under both `/scan` and `/history`.

*Why:* a fresh scan and a history entry must be visually identical, otherwise
the user cannot trust that the stored record is what they saw. Routing it under
both branches (rather than pushing across branches) keeps the correct tab
highlighted and the back stack sane with `indexedStack`.

### 5.12 `drift_flutter` instead of `sqlite3_flutter_libs`

The database connection comes from `driftDatabase(name: 'allergy_scanner')`.

*Why:* the house-style dependency `sqlite3_flutter_libs` is end-of-life
(`0.6.0+eol`) and, from `package:sqlite3` 3.x on, does nothing at all.
`drift_flutter` is what drift's current setup documentation prescribes, and it
also replaces the hand-written `NativeDatabase(file)` plus `path_provider`
opener.

*Consequence for the old trap:* the house rule "never
`NativeDatabase.createInBackground()`" survives — `driftDatabase` opens on the
calling isolate unless `shareAcrossIsolates: true` is passed, and it is not
passed. This must still be confirmed on the first release build.

*Rejected:* keeping the EOL package (it would be a no-op dependency that
implies a guarantee it no longer provides).

### 5.13 The disclaimer is a gate in the shell, not a route

`AdaptiveShell` renders `DisclaimerScreen` while
`settings.disclaimerAcknowledgedAt` is null.

*Why:* as a route it would need a `redirect` that races the settings stream —
after acknowledgement the redirect can still see the old value and bounce the
user back, which is the classic go_router loop. As a gate it covers every tab
and every deep link by construction, and acknowledgement simply makes the
stream emit and the shell rebuild.

*Rejected:* `redirect` plus a `refreshListenable` bridging the stream (more
moving parts for the same result), and a second `MaterialApp` before the
router (two navigators, two themes to keep in sync).

### 5.14 Two platforms, not five

v0.1 builds Android and iOS only.

*Why:* ML Kit covers no desktop platform and `mobile_scanner` covers only
macOS, so a desktop build would ship without one or both of the app's two
headline features. See REQUIREMENTS §3.

*Consequence:* the house rule of five platforms × two modes is deviated from,
which is recorded in the README, in `CLAUDE.md` and in `build.yml` itself. The
adaptive 600 dp layout stays — for tablets and landscape phones, not for a
desktop target.

---

## 6. Navigation map

```
StatefulShellRoute.indexedStack → AdaptiveShell
│                                  └── DisclaimerScreen while not acknowledged
├── branch 0  /scan
│              /scan/barcode                 camera, registered only if capable
│              /scan/text                     photo → OCR, registered if capable
│              /scan/review                   editable recognised/typed text
│              /scan/manual                   barcode or text entry
│              /scan/result/:scanId           ScanResultScreen
│              /scan/result/:scanId/product   product correction
├── branch 1  /allergies
│              /allergies/add
│              /allergies/:termId/edit
├── branch 2  /history
│              /history/:scanId               ScanResultScreen (same widget)
└── branch 3  /settings
               /settings/backup
               /settings/sync
               /settings/about
               /settings/privacy
               /settings/logs
```

- `initialLocation` is `/scan`. The disclaimer is a gate inside the shell
  rather than a route (§5.13).
- Camera routes are added to the router **only** when `ScanCapabilities` allows
  them (§5.8).
- Path parameters are read as `state.pathParameters['scanId']!`. `state.extra`
  carries the recognised text into `/scan/review`, the `ScanLookupProblem` into
  a result, and the barcode into the product correction screen.

---

## 7. Bootstrap and provider overrides

`main.dart`, in order: `runZonedGuarded` → `ensureInitialized()` → file logger
(+ `debugPrint` redirect, `FlutterError.onError` chaining to the original
handler) → GPL notice via `LicenseRegistry.addLicense` → `AppDatabase()` →
shared `Dio` with 15 s connect/receive timeouts and the mandatory Open Food
Facts `User-Agent` → services → `runApp(ProviderScope(overrides: [...]))`.

Providers that **must** be overridden at startup — each declared as
`Provider<T>((_) => throw UnimplementedError('<name> must be overridden'))`
so a missing override fails loudly instead of quietly constructing a real
network client in a test:

| Provider | Type |
|---|---|
| `appDatabaseProvider` | `AppDatabase` |
| `logServiceProvider` | `LogService` |
| `dioProvider` | `Dio` |
| `appVersionProvider` | `AppVersion` |
| `openFoodFactsServiceProvider` | `OpenFoodFactsService` |
| `textRecognitionServiceProvider` | `MlKitTextRecognitionService` or `UnsupportedTextRecognitionService` |
| `backupServiceProvider` | `BackupService` |
| `webdavServiceProvider` | `WebdavService` |
| `secureStorageProvider` | `FlutterSecureStorage` |

`scanCapabilitiesProvider` has a working platform-derived default and is
overridden only so `main.dart` and the router agree on one instance, and so
tests can inject `ScanCapabilities.none()`.

`main.dart` also calls `settingsDao.ensureDefaults(deviceLanguage: …)` once, so
the preferred ingredient language starts at the device locale without a read
ever writing to the database.

The provider graph itself is in `doc/CLASS_DIAGRAM.md`.

---

## 8. Testing

Layout mirrors `lib/`:

```
src/test/
├── calculators/  text_normalizer_test.dart, allergen_matcher_test.dart
├── database/     test_database.dart (in-memory factory + builders),
│                 allergen_term_dao_test.dart, product_dao_test.dart,
│                 scan_dao_test.dart, settings_dao_test.dart
├── services/     open_food_facts_service_test.dart (loopback HttpServer),
│                 backup_service_test.dart (in-memory round trip)
└── widget_test.dart   shell smoke test with every provider overridden
```

A migration test is not present yet: `schemaVersion` is 1, so there is no
`onUpgrade` step to exercise. The first schema change adds it.

Strategy:

- The **matcher and normaliser are tested rule by rule** against
  REQUIREMENTS §5 — accents, `ß`, punctuation and newlines from OCR, the
  3-character floor, offsets, the three verdicts, the empty-term-list case, and
  the accepted `nut`/`coconut` false positive as a *pinned* expectation so a
  future change to it is deliberate.
- DAOs run against `AppDatabase.forTesting(NativeDatabase.memory())` with
  foreign keys enabled, including the `setNull`/`cascade` behaviour of §5.5.
- The Open Food Facts client is tested against a real loopback `HttpServer`
  serving recorded payloads — success, missing `ingredients_text`, unknown
  barcode, 429, 500 and a dropped connection — asserting the sealed result
  variant for each. No mocked `Dio`.
- The backup round trip asserts that no credential ends up in the archive.

What is **not** tested, and why:

- **ML Kit recognition quality** — it is a native black box; only the wrapper's
  "no text found" and error paths are covered, through a fake
  `TextRecognitionService`.
- **Camera and permission flows** — plugin and OS behaviour; verified manually
  per platform.
- **WebDAV** — neither the request building nor the fingerprint check has a
  test yet; the PROPFIND name extraction is a regular expression over the
  response body and deserves one. End-to-end sync against a real Nextcloud
  stays a manual check.
- **`ScanActions`** — the pipeline is exercised only through its parts (matcher,
  DAOs, Open Food Facts client). A test with a fake `OpenFoodFactsService`
  covering "transient failure with a cached product" and "manual override wins"
  is the most valuable one still missing.
- **Platform builds** — CI proves that Android and iOS compile; nothing asserts
  runtime behaviour beyond a manual smoke run.
