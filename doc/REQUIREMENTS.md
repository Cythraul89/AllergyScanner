# AllergyScanner — Requirements

Offline-first mobile app that checks a packaged product against the
user's own list of allergy-relevant substances. The product's ingredient text
is obtained either from a barcode lookup or from the camera via on-device text
recognition, and is matched locally against the user's terms.

Status: requirements draft for v0.1. No code exists yet.
Repository: `AllergyApp` · display name: `AllergyScanner` ·
pubspec name: `allergy_scanner` · package/artifact name: `allergy-scanner`.

---

## 1. Scope

### 1.1 In scope for v0.1

| # | Capability |
|---|---|
| 1 | Manage a user-defined list of allergy terms (free text) |
| 2 | Scan a product barcode with the camera and fetch its data from Open Food Facts |
| 3 | Scan a printed ingredient list with the camera (on-device OCR) |
| 4 | Enter or paste a barcode / ingredient text manually on every platform |
| 5 | Match the ingredient text against the user's terms and show a clear verdict |
| 6 | Persist a scan history that stays readable offline |
| 7 | Correct or complete a product locally; local data always wins over remote |
| 8 | Local ZIP backup (export / import) of all app data |
| 9 | Optional Nextcloud/WebDAV sync of the same ZIP backup |
| 10 | Settings with theme, About, in-app log viewer, backup and sync |

### 1.2 Explicitly out of scope for v0.1

- No user accounts, no cloud profile, no telemetry, no analytics.
- No AI/LLM interpretation of ingredient lists.
- No notifications and no background work (nothing in this app is
  time-triggered).
- No writing back to Open Food Facts (read-only client).
- No nutrition, additive, diet (vegan/halal) or calorie evaluation.
- No seeded allergen catalogue (e.g. the 14 EU-declared allergens) — see
  §11 item 1. Grouping several names under one allergen, with translation
  *suggestions*, is delivered (§4.1, §5.4); the app still ships with no
  pre-populated terms or groups.

---

## 2. Users and primary flows

One local user per installation (no multi-profile in v0.1).

```
F1  Barcode flow
    Scan tab → camera → barcode detected → local product lookup
      hit  → evaluate cached/overridden ingredient text
      miss → fetch from Open Food Facts → cache → evaluate
      miss + offline / not found → "unknown product" → offer OCR or manual entry

F2  Ingredient-text flow
    Scan tab → "Scan ingredient list" → camera → on-device OCR →
    editable recognised text → evaluate

F3  Manual flow (all platforms, always available)
    Scan tab → "Enter manually" → barcode field or ingredient text field →
    evaluate

F4  Profile flow
    Allergies tab → add / edit / deactivate / delete a term

F5  History flow
    History tab → list of past scans → open a scan → same result view, offline
```

---

## 3. Platform support and capability matrix

Two platforms are targeted — **Android and iOS** — each with a debug and a
release artifact. **macOS, Windows and Linux are out of scope** (project
decision, see below). Both supported platforms have the full feature set.

| Platform | Barcode via camera | Ingredient OCR via camera | Manual entry | Notes |
|---|---|---|---|---|
| Android | yes | yes | yes | Full feature set |
| iOS | yes | yes | yes | Full feature set; release build is unsigned in CI |

Verified 2026-08-20 on pub.dev: `mobile_scanner` 7.4.0 supports Android, iOS,
macOS and web (not Linux, not Windows); `google_mlkit_text_recognition` 0.17.1
supports Android and iOS only.

**Why the desktop platforms are dropped.** ML Kit covers no desktop platform at
all, and `mobile_scanner` covers only macOS — so Linux and Windows would have
neither scanning feature, and macOS would have barcode scanning but no
ingredient-list recognition. Rather than ship three platforms with a partial
feature set, v0.1 is mobile-only. The house rule of five platforms is therefore
deliberately deviated from; the deviation is recorded here, in `CLAUDE.md` and
in the README rather than silently omitted from the build matrix. Re-adding a
desktop platform requires a desktop OCR backend and, for Windows and Linux, a
desktop barcode input path (§11, planned features 3 and 4).

Manual barcode and manual ingredient-text entry remain first-class features on
mobile — they are how a damaged barcode, an unlisted product or a failed
recognition is handled, not a desktop fallback.

Requirements derived from the matrix:

- **R3.1** Every camera entry point is hidden, not disabled-with-error, on a
  platform that cannot provide it. The manual equivalent is always present.
- **R3.2** Capability is queried through one `ScanCapabilities` value in
  `core/`, derived from `Platform.*` — never from ad-hoc `Platform.isAndroid`
  checks scattered through the UI. It stays in place although both supported
  platforms currently answer "yes" to everything: it is what keeps R3.1
  enforceable when a platform is added back.
- **R3.3** Matching, storage, history, backup and sync behave identically on
  both platforms.
- **R3.4** The layout is adaptive at 600 dp (`kDesktopBreakpoint`) for tablets
  and landscape phones, not because a desktop platform is targeted.

---

## 4. Data model

SQLite via Drift. String UUID primary keys except where noted. Timestamps are
stored as UTC `DateTime`. No monetary values exist in this app, so `decimal` is
not a dependency.

### 4.1 `allergen_terms` — the user's allergy list

| Field | Type | Notes |
|---|---|---|
| `id` | text, PK | UUID v4 |
| `term` | text, not null | Exactly as the user typed it; shown in the UI |
| `normalizedTerm` | text, not null | Result of §5.2 normalisation; the matcher reads only this |
| `isActive` | bool, not null, default `true` | Inactive terms are kept but not matched |
| `note` | text, nullable | Free remark, e.g. "severe" |
| `groupId` | text, nullable | FK → `allergen_groups.id`, `onDelete: setNull`; `null` = ungrouped |
| `createdAt` | datetime, not null | |
| `updatedAt` | datetime, not null | |

- **R4.1** `normalizedTerm` is unique. Adding a term that normalises to an
  existing one is rejected with a message naming the existing entry.
- **R4.2** A term whose normalised form is shorter than 3 characters is
  rejected (§5.5).
- **R4.3** `normalizedTerm` is recomputed on every write of `term`. It is
  never edited directly by the user.
- **R4.3a** Matching stays per-term, unchanged by grouping — a group is an
  organisational label, not a matching-rule change (§5.4).

### 4.1a `allergen_groups` — names for the same allergen, in several languages

| Field | Type | Notes |
|---|---|---|
| `id` | text, PK | UUID v4 |
| `label` | text, not null | Display name, e.g. "Hazelnut"; not matched, not required to be unique |
| `createdAt` | datetime, not null | |
| `updatedAt` | datetime, not null | |

- **R4.1b** Deleting a group ungroups its member terms (FK `setNull`); it
  never deletes them.
- **R4.1c** Adding a member name may be assisted by a DE/EN/FR/IT translation
  *suggestion* from an online, keyless service (MyMemory), gated on
  `remoteLookupEnabled` (§6.6) exactly like the Open Food Facts lookup — no
  suggestion is ever inserted automatically, the user always reviews it
  first through the same duplicate/length checks as any other term (R4.1,
  R4.2).

### 4.2 `products` — Open Food Facts cache and local overrides

| Field | Type | Notes |
|---|---|---|
| `barcode` | text, PK | EAN-8/13, UPC-A/E, GTIN-14 as reported by the scanner |
| `productName` | text, nullable | |
| `brands` | text, nullable | |
| `quantity` | text, nullable | e.g. "200 g" |
| `ingredientsText` | text, nullable | The text the matcher evaluates |
| `ingredientsLanguage` | text, nullable | Language tag of `ingredientsText` (§6.4) |
| `allergensTags` | text, nullable | Open Food Facts tags, newline-separated, informational only |
| `tracesTags` | text, nullable | Same, for "may contain" declarations |
| `imageUrl` | text, nullable | Not downloaded in v0.1 |
| `source` | int (enum), not null | `openFoodFacts` \| `manual` |
| `hasManualOverride` | bool, not null, default `false` | |
| `fetchedAt` | datetime, nullable | When remote data was last retrieved |
| `updatedAt` | datetime, not null | |

- **R4.4** A row with `hasManualOverride = true` is never overwritten by a
  fetch and is never considered stale. A fetch on such a row updates nothing
  but may be offered to the user as "remote data differs — replace?".
- **R4.5** Remote data is stale after 30 days (`kProductCacheTtl`); a stale
  row is still used immediately for the verdict, and a refresh is attempted in
  the background only when the user triggers the scan online.
- **R4.6** Editing a product locally sets `hasManualOverride = true` and
  leaves `source` unchanged, so provenance stays visible.

### 4.3 `scans` — history

| Field | Type | Notes |
|---|---|---|
| `id` | text, PK | UUID v4 |
| `scannedAt` | datetime, not null | |
| `inputMode` | int (enum), not null | `barcode` \| `ocr` \| `manualText` \| `manualBarcode` |
| `barcode` | text, nullable | FK → `products.barcode`, `onDelete: setNull` |
| `productNameSnapshot` | text, nullable | Frozen at scan time |
| `evaluatedText` | text, not null | Exactly the text that was matched |
| `verdict` | int (enum), not null | `hit` \| `noMatch` \| `unknown` (§5.6) |
| `matchCount` | int, not null | Denormalised count of `scan_matches` |
| `name` | text, nullable | User-entered label, set after the fact via *Edit details* |
| `shop` | text, nullable | Free text; groups history entries that share the same value (§7.4) |
| `photoPath` | text, nullable | Relative path under the app documents dir to a user-attached photo; set only via *Edit details*, never at scan time |

- **R4.7** History is self-contained: deleting a product or an allergy term
  never makes a past scan unreadable (§4.4).
- **R4.8** History is capped at `kMaxScanHistory = 500` entries; the oldest
  are pruned on insert. The cap is shown in Settings.
- **R4.11** A scan's `name`, `shop` and `photoPath` are set after the fact via
  *Edit details*, never at scan time; editing them never re-evaluates the
  verdict and never touches `evaluatedText`, so R4.7's snapshot guarantee is
  unaffected.
- **R4.12** Deleting a scan (single, clear-all, or pruning past
  `kMaxScanHistory`) deletes its attached photo file, if any — no orphaned
  file survives its scan row.

### 4.4 `scan_matches` — one row per hit inside a scan

| Field | Type | Notes |
|---|---|---|
| `id` | text, PK | UUID v4 |
| `scanId` | text, not null | FK → `scans.id`, `onDelete: cascade` |
| `allergenTermId` | text, nullable | FK → `allergen_terms.id`, `onDelete: setNull` |
| `termSnapshot` | text, not null | The term as it read at scan time |
| `matchedText` | text, not null | The substring found in `evaluatedText` |
| `startOffset` | int, not null | Offset into the normalised text, for highlighting |
| `endOffset` | int, not null | Exclusive |

### 4.5 `settings` — single row, `id = 1`

| Field | Type | Default | Notes |
|---|---|---|---|
| `themeMode` | int (enum) | `system` | |
| `preferredIngredientsLanguage` | text | device locale language | §6.4 |
| `remoteLookupEnabled` | bool | `true` | `false` = fully offline, no HTTP at all |
| `disclaimerAcknowledgedAt` | datetime, nullable | `null` | §1.3 |
| `webdavBaseUrl` | text, nullable | `null` | |
| `webdavUsername` | text, nullable | `null` | Password lives in secure storage |
| `certificateFingerprint` | text, nullable | `null` | SHA-256, self-signed servers |
| `lastSyncAt` | datetime, nullable | `null` | |

- **R4.9** The WebDAV password and nothing else goes into
  `flutter_secure_storage`. No credential is ever written to SQLite, to a log
  or into a backup archive.

---

## 5. Matching rules

The matcher is a pure calculator (`core/calculators/allergen_matcher.dart`),
does no I/O, and is unit-tested directly. Every rule below is a test case.

- **R5.1** Input is the evaluated text plus the list of active allergy terms.
  Output is an ordered list of matches (by `startOffset`) and a verdict.

### 5.2 Normalisation (applied to both sides)

Applied in this order, to the term and to the ingredient text alike:

1. Unicode NFKD decomposition, then removal of combining marks —
   `Nuß`/`nuss` and `Sésame`/`sesame` must not differ by accent alone.
2. Lowercase.
3. German umlaut folding after step 1 leaves `ss` for `ß`.
4. Replace every character that is neither a letter nor a digit with a single
   space (this removes `(`, `)`, `,`, `*`, `-`, `.` and newlines from OCR).
5. Collapse runs of whitespace to one space; trim.

- **R5.2** Normalisation is a single pure function used by the matcher, by the
  term-uniqueness check (§4.1) and by nothing else.

### 5.3 Match rule

- **R5.3** A term matches if its normalised form occurs as a substring of the
  normalised text. Case, accents and punctuation are therefore irrelevant.
- **R5.4** Offsets refer to the normalised text; the UI highlights on the
  normalised text so the highlight cannot drift out of sync.

### 5.4 Known limitation (accepted for v0.1)

Plain substring matching was chosen deliberately over an alias dictionary. The
consequences are stated here so they are not rediscovered as bugs:

- **False negatives**: Latin names (`Corylus avellana` for hazelnut),
  E-numbers (`E322` for lecithin), translations, and paraphrases are **not**
  found unless the user adds them as separate terms.
- **False positives**: a short term is found inside an unrelated word —
  `nut` matches `coconut` and `butternut`. §5.5 limits, but does not remove,
  this effect.
- **"May contain" wording** is only found if the substance itself appears in
  the text; `tracesTags` from Open Food Facts is displayed but not matched.

The UI must therefore never claim a product is safe (§5.6, §7.2), and the
alias feature is listed in §11. Grouping several names under one allergen
(§4.1a) is an organisational/UI convenience over this per-term substring
rule, not a change to it — each name in a group still needs to appear
literally in the text; the app never infers that a match on one name implies
a match on its synonyms.

### 5.5 Guard rails

- **R5.5** Terms shorter than 3 normalised characters are rejected at entry.
- **R5.6** When a term matches, the result view shows the surrounding
  ingredient text so the user can judge a false positive.

### 5.6 Verdict

| Verdict | Condition | Wording requirement |
|---|---|---|
| `hit` | ≥ 1 match | "Contains terms from your list" + the list of hits |
| `noMatch` | Text present, non-empty after normalisation, no match | "No term from your list found" — **never** "safe" or "free from" |
| `unknown` | No ingredient text available (product not found, empty field, OCR produced nothing) | "Could not be checked" + the reason + next-step buttons |

- **R5.7** An empty allergy list produces `unknown`, not `noMatch`, and the
  result view links to the Allergies tab.

### 5.7 Ingredients-marker gate (before matching)

- **R5.8** Before OCR or manually entered text is evaluated, it is scanned
  (unnormalised, case-insensitive) for one of four literal section markers —
  `Ingredients:`, `Zutaten:`, `Ingrédients:` (accent optional), `Ingredienti:`
  — the word, an optional space, and a colon. Plain literal/regex search, not
  language-model interpretation (§1.2).
- **R5.9** If no marker is found, the text is not evaluated: the review
  screen's *Check* action stays disabled until the user edits the text to add
  a recognised marker, or re-scans. This is enforced entirely in the review
  screen, before `ScanActions.evaluate` is called (doc/ARCHITECTURE.md §5.9)
  — a blocked attempt is never written to history (R7.7 does not apply to
  it). This gate applies identically to OCR and to manually entered/pasted
  text (§6 below).

---

## 6. Barcode lookup (Open Food Facts)

- **R6.1** One injectable service (`core/services/open_food_facts_service.dart`)
  constructed with a shared `Dio`. It returns a sealed result and never shows
  UI:

  | Result | Meaning | UI consequence |
  |---|---|---|
  | `OffSuccess(product)` | Server answered, product exists | Cache and evaluate |
  | `OffNotFound()` | Server answered, no such barcode | `unknown` + offer OCR/manual |
  | `OffTransient()` | Offline, timeout, 5xx, rate-limited | `unknown` + "retry" — must **not** read as "not found" |
  | `OffFailure(message)` | Anything else, logged | `unknown` + message |

  `OffNotFound` and `OffTransient` are never collapsed into one code path.
- **R6.2** Endpoint: `GET https://world.openfoodfacts.org/api/v3/product/{barcode}.json`
  with an explicit `fields` query so only what §4.2 stores is transferred.
  Expected fields: `product_name`, `brands`, `quantity`, `ingredients_text`,
  `ingredients_text_<lang>`, `allergens_tags`, `traces_tags`, `image_url`.
  *Unverified:* the exact v3 response envelope (top-level keys, how
  "not found" is signalled) must be confirmed against a live response during
  implementation; the field names above are taken from the documented data
  model, not from a response captured for this project.
- **R6.3** A custom `User-Agent` of the form
  `AllergyScanner/<version> (<contact>)` is mandatory on every request
  (Open Food Facts policy). The contact address is a build-time constant.
- **R6.4** The documented read limit is 15 requests/min/IP. The client
  enforces a local minimum interval between product requests and surfaces
  `OffTransient` instead of hammering. No bulk or search requests in v0.1.
- **R6.5** Timeouts: connect 15 s, receive 15 s. Every caught error is logged
  through the app logger; `print` is never used.
- **R6.6** With `remoteLookupEnabled = false` the service is not called at
  all — a barcode scan then resolves only against the local `products` table.
- **R6.7** Language choice: prefer `ingredients_text_<preferred>`, then
  `ingredients_text`, then any other `ingredients_text_*`; store which one was
  used in `ingredientsLanguage` and show it in the result view.

---

## 7. Screens

Four shell destinations: **Scan**, **Allergies**, **History**, **Settings**.
Wireframes belong in `doc/SCREENS.md`; this section fixes the behaviour.

### 7.1 Scan (start destination)

- Primary actions: *Scan barcode* / *Scan ingredient list* (only where §3
  allows) and *Enter manually* (always).
- **R7.1** Camera permission is requested at the moment of use, not at
  startup. A denial shows the manual path plus a link to system settings.
- **R7.2** A detected barcode ends the camera session immediately; there is no
  continuous re-scan loop.
- **R7.3** OCR output is presented in an **editable** text field before
  evaluation — recognition errors must be fixable without a re-scan.
- **R7.12** When a marker is found (R5.8), the review screen shows a live
  preview of the detected section with matches against the active allergy
  list highlighted inline, using the same normalised-text offsets as the
  result view (R5.4); colour is never the only signal (R7.4). The preview
  carries an explicit caveat that the full text is checked again on *Check*
  — the preview's section boundary never narrows what is actually
  evaluated. When no marker is found (R5.9), the screen names the four
  recognised markers and disables *Check*; the fix happens in the same
  field (R7.3), never a separate dialog.

### 7.2 Result view

- **R7.4** The verdict is stated in text and by colour; colour alone never
  carries the verdict. `hit` uses `colorScheme.error`; `noMatch` uses the
  semantic green accent; `unknown` is neutral.
- **R7.5** Shows: verdict, matched terms with context, product name/brand when
  known, the evaluated text (collapsible), the data source
  (`Open Food Facts, fetched <date>` / `manual` / `OCR` / `typed`), the
  `allergens_tags` / `traces_tags` as separate informational chips, and the
  §1.3 disclaimer line.
- **R7.6** Actions: *Correct product data* (barcode scans), *Edit details*
  (name/shop/photo, every scan), *Re-scan*,
  *Add a matched-looking word to my list*, *Delete this scan*.
- **R7.7** Every scan is written to history before the result view is shown,
  so a crash cannot lose it.
- **R7.13** When set, a scan's name/shop are shown near the top of the
  result view, and its attached photo (if any) as a thumbnail — distinct
  from the OCR capture photo, which is never persisted (N10/N10a).

### 7.3 Allergies

- **R7.8** List of terms, active ones first, with an add/edit sheet, an
  active toggle, swipe-to-delete with undo, and a search field. Terms may be
  organised into groups (§4.1a); the screen shows one collapsible section
  per group, then an "Other terms" section for ungrouped terms, unchanged in
  rendering from today's flat list.
- **R7.9** Deleting a term does not alter past scans (§4.4). Deleting a
  group (R4.1b) does not delete its member terms.

### 7.4 History

- **R7.10** History is grouped by shop (R7.14) and, within each shop group,
  reverse-chronological, showing date, name/product/"text scan", verdict
  badge and match count; filterable by verdict; opens the stored result view
  without any network access.
- **R7.14** Scans sharing the same (trimmed) `shop` value are grouped
  together automatically, each group headed by its shop name and ordered by
  its own most-recent scan; scans with no `shop` set are grouped under
  "Ungrouped". Because every existing scan has no `shop` value until the
  user starts using it, this is visually a single added header line for
  anyone not yet using the field, not a reordering of their history. Purely
  a display transform of the already-fetched, already reverse-chronological
  list — no new table, no new query.

### 7.5 Settings

- **R7.11** Theme (system/light/dark), preferred ingredient language, remote
  lookup on/off, local backup (export/import), Nextcloud sync, About
  (version, licence, privacy, disclaimer), log viewer.

---

## 8. Backup, export and sync

- **R8.1** Local ZIP export contains all four data tables plus settings
  (without secrets) as JSON, and a manifest with app version, schema version
  and archive format version (`backupFormatVersion`, currently 2 —
  independent of the schema version). Any history photo a scan has attached
  travels as its own archive entry (raw bytes, named after its own
  `photoPath`), not embedded in the JSON. Filename:
  `allergy_scanner_YYYYMMDD_HHmmss.zip`.
- **R8.2** Import is transactional, refuses an archive with a newer schema
  version or a newer archive format version than the app, and reports a
  skip count for rows it could not attach; the caller surfaces that count
  when > 0. An archive with no `name`/`shop`/`photoPath` fields and no photo
  entries (written before backup format version 2) still imports correctly
  — those fields are simply absent, read as `null`.
- **R8.3** Nextcloud/WebDAV sync uploads and downloads exactly that archive
  over basic auth. Optional SHA-256 certificate pinning for self-signed
  servers; a fingerprint mismatch rejects the connection.
- **R8.4** Sync flow: test connection → certificate dialog if untrusted →
  verify credentials → save → look for a remote backup → offer
  restore/upload/later → record `lastSyncAt` so the startup check does not
  immediately re-prompt.
- **R8.5** Sync is entirely optional; every feature works with it unconfigured
  and with no network at all.

---

## 9. Non-functional requirements

| # | Requirement |
|---|---|
| N1 | Offline first: launch, allergy list, matching, history, manual entry and OCR work with no network. Only barcode lookup of an uncached product needs it. |
| N2 | No accounts, no telemetry, no third-party analytics. Outbound hosts are Open Food Facts, the user's own WebDAV server, and MyMemory (translation *suggestions* for allergen group names, §4.1c) — all three gated on `remoteLookupEnabled` (R6.6); with it off, none is called. |
| N3 | A scan of already-cached data produces a verdict without a network round trip; matching a 5 000-character ingredient text against 100 terms stays imperceptible (target < 50 ms). |
| N4 | `flutter analyze --fatal-infos` clean; no `// ignore` used to reach it. |
| N5 | Unit tests cover the normaliser, the matcher (§5 rule by rule), the Open Food Facts response mapping against a loopback `HttpServer`, and every DAO against an in-memory database. |
| N6 | Material 3, indigo seed, light + dark, `themeMode` from the settings table. |
| N7 | Two platforms (Android, iOS) × debug + release in one reusable `build.yml`; the dropped platforms of §3 are stated in the README. |
| N8 | Licence GPL-3.0. |
| N9 | Accessibility: verdict never conveyed by colour alone; all controls labelled for screen readers; text scales without clipping. |
| N10 | Privacy — camera capture for scanning: a photo taken for barcode or ingredient-text (OCR) recognition is processed entirely on-device and deleted immediately after use; it is never stored or uploaded. |
| N10a | Privacy — attached photos: separately and only when the user chooses to, a photo may be attached to a history entry after the fact (*Edit details*, e.g. a photo of the receipt or shelf). Unlike N10's capture photo, this one **is** stored on-device — never uploaded on its own — until the user removes it or deletes the scan it belongs to; it leaves the device only inside a backup archive the user explicitly exports or syncs (§8). Only the barcode digits ever leave the device on their own, and only when remote lookup is enabled. `PRIVACY.md` plus an in-app privacy screen state both N10 and N10a. |

---

## 10. Permissions per platform

| Platform | Permission | Reason |
|---|---|---|
| Android | `android.permission.CAMERA` | Barcode and OCR scanning |
| Android | `android.permission.INTERNET` | Open Food Facts, WebDAV |
| iOS | `NSCameraUsageDescription` | Barcode and OCR scanning |
| iOS | `NSPhotoLibraryUsageDescription` | Reading an ingredient list from an image the user picks |

- **R10.1** These are applied as patch steps in `build.yml`; platform folders
  are not committed.

---

## 11. Planned features (post-v0.1)

Delivered items are marked `✓ *(delivered)*` rather than deleted, so this
section doubles as a change history.

1. **Alias/synonym lists per term** — the direct fix for §5.4: Latin names,
   E-numbers, translations, with a seeded catalogue of the 14 allergens the
   EU requires to be declared, which the user can enable and extend.
   ✓ *(partially delivered)* — grouping several names under one allergen
   (§4.1a) and translation-assisted synonym entry (§4.1c, an online MyMemory
   suggestion the user reviews before it becomes a term) are delivered.
   **Not** delivered: the seeded 14-EU-allergen catalogue — translating
   legally-significant allergen names via a best-effort MT API is not
   something to seed automatically; a hand-curated, offline, deterministic
   seed table (N1 requires first-run to work without a network) is a
   separate follow-up with its own review surface.
2. **Word-boundary and stemming options** to reduce `nut`/`coconut`-style
   false positives.
3. **Desktop OCR** — a second `TextRecognitionService` implementation taking an
   image file, which is what makes macOS (barcode already supported by
   `mobile_scanner`) worth adding back.
4. **Windows and Linux support**, which needs both the desktop OCR backend (3)
   and a desktop barcode input path — an attached USB scanner (keyboard wedge)
   or barcode detection from an image file.
5. **Multiple profiles** (e.g. one per family member) with a profile switch in
   the scan flow.
6. **Product data contribution** back to Open Food Facts for products the user
   corrected locally.
7. **Offline Open Food Facts subset import** from the published CSV/JSONL
   dump, for use without any network.
8. **Shopping-list check** — evaluate several products in one session.
9. **Barcode history deduplication** and a "products I scanned" browse view.

---

## 12. Open questions

| # | Question | Blocks |
|---|---|---|
| Q1 | Contact address to put into the mandatory Open Food Facts `User-Agent` (§6.3) — a real, monitored address is expected by their policy. | Implementation of the service |
| Q2 | Should a `hit` verdict be additionally confirmed by a full-screen warning (harder to miss, more taps) or stay an inline banner? | Result-view design |
| Q3 | Exact Open Food Facts v3 response envelope (§6.2) — to be captured from a live request. | Response mapping + its test |
