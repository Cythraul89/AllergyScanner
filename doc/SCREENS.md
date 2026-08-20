# AllergyScanner — Screens

Wireframes and behaviour per screen. Requirement IDs in brackets refer to
`doc/REQUIREMENTS.md`. The compact layout is `< 600 dp` (bottom
`NavigationBar`), the wide one is `>= 600 dp` (`NavigationRail`, extended above
~1200 dp) and applies to tablets and landscape phones — v0.1 targets Android
and iOS only. Only screens whose layout actually differs get a second
wireframe; "desktop" below means that wide layout.

Four shell destinations: **Scan** (start) · **Allergies** · **History** ·
**Settings**.

---

## 1. First launch — disclaimer

Shown once, before the shell, when `settings.disclaimerAcknowledgedAt` is
`null` [R1.3 / §4.5].

```
┌────────────────────────────────────────┐
│                                        │
│              ⚠  AllergyScanner         │
│                                        │
│  This app matches text against terms   │
│  you enter. It does not decide whether │
│  a product is safe for you to eat.     │
│                                        │
│  • Product data comes from Open Food   │
│    Facts and is not verified.          │
│  • Recognised text can be incomplete   │
│    or wrong.                           │
│  • Only the exact words you list are   │
│    found — not their synonyms.         │
│                                        │
│  Always read the packaging.            │
│                                        │
│         [ I understand ]               │
└────────────────────────────────────────┘
```

**Behaviour**

- `I understand` writes `disclaimerAcknowledgedAt`; the settings stream emits
  and the shell renders its content.
- No dismiss, no back. It is **not a route**: `AdaptiveShell` renders it in
  place of the shell content while the acknowledgement is missing, which covers
  every tab and every deep link (see ARCHITECTURE §5.13).
- The same text is reachable again any time via Settings → About [R7.11].

---

## 2. Scan (start destination)

### Mobile

```
┌────────────────────────────────────────┐
│ AllergyScanner                         │
├────────────────────────────────────────┤
│                                        │
│   ┌──────────────────────────────────┐ │
│   │  ▣  Scan barcode                 │ │
│   │     Look up the product          │ │
│   └──────────────────────────────────┘ │
│   ┌──────────────────────────────────┐ │
│   │  ⌸  Scan ingredient list         │ │
│   │     Read the text on the pack    │ │
│   └──────────────────────────────────┘ │
│   ┌──────────────────────────────────┐ │
│   │  ⌨  Enter manually               │ │
│   │     Barcode or ingredient text   │ │
│   └──────────────────────────────────┘ │
│                                        │
│  Your list: 7 active terms             │
│  ⚠ No terms yet — add one first        │
│                                        │
│  Recent                                │
│  ─────────────────────────────────     │
│  ● Choco Bar 200g        today 14:02   │
│  ○ text scan             today 09:11   │
│                                        │
├────────────────────────────────────────┤
│  [Scan]  Allergies  History  Settings  │
└────────────────────────────────────────┘
```

### Desktop (>= 600 dp)

```
┌──────┬─────────────────────────────────────────────────────────────┐
│ ▣    │ AllergyScanner                                              │
│ Scan ├─────────────────────────────────────────────────────────────┤
│      │                                                             │
│ ☰    │  ┌──────────────────────────────────────────────┐           │
│ Aller│  │ ▣  Scan barcode — look up the product         │           │
│ gies │  ├──────────────────────────────────────────────┤           │
│      │  │ ⌸  Scan ingredient list — read the pack       │           │
│ ⏱    │  ├──────────────────────────────────────────────┤           │
│ Hist │  │ ⌨  Enter manually — barcode or text           │           │
│ ory  │  └──────────────────────────────────────────────┘           │
│      │                                                             │
│ ⚙    │  Your list: 7 active terms                                  │
│ Sett │                                                             │
│ ings │  Recent                                                     │
│      │  ● Choco Bar 200g                            today 14:02    │
│      │  ○ text scan                                 today 09:11    │
└──────┴─────────────────────────────────────────────────────────────┘
```

The wide layout differs only in the navigation rail; the cards are the same
list. A platform without a camera would show just *Enter manually* plus an
explanatory line — no such platform is targeted in v0.1, but the code path
exists and the widget test covers it [R3.1].

**Behaviour**

- Entry cards for camera actions are **hidden**, not disabled, where the
  platform cannot provide them [R3.1]; capability comes from
  `ScanCapabilities` [R3.2]. Where neither camera feature exists, only
  *Enter manually* remains and the explanatory line above is shown — no such
  platform ships in v0.1.
- `Your list: N active terms` taps through to Allergies. With zero active terms
  a warning row appears and every scan would end in `unknown` [R5.7].
- `Recent` shows the newest 3 scans; verdict dot: filled = `hit`,
  hollow = `noMatch`, `?` = `unknown`. Tapping opens the stored result.
- Empty state: no `Recent` block at all, no placeholder card.

---

## 3. Camera — barcode

```
┌────────────────────────────────────────┐
│ ← Scan barcode                    [⚡] │
├────────────────────────────────────────┤
│                                        │
│        ┌────────────────────┐          │
│        │                    │          │
│        │   camera preview   │          │
│        │  ┌──────────────┐  │          │
│        │  │   ▮▮ ▮ ▮▮▮   │  │          │
│        │  └──────────────┘  │          │
│        │                    │          │
│        └────────────────────┘          │
│                                        │
│   Point at the barcode on the pack     │
│                                        │
│         [ Enter manually ]             │
└────────────────────────────────────────┘
```

**Behaviour**

- Camera permission is requested by `mobile_scanner` on entering this route,
  not at app start [R7.1]. Denied → the plugin's own error state is shown and
  the `Enter manually` button below the preview stays the way forward. No
  separate permission stack is used, so there is no "open system settings"
  action; adding one would mean a second permission plugin.
- First detected barcode stops the session immediately; no continuous loop
  [R7.2]. Haptic feedback on detection.
- `⚡` toggles the torch where the platform supports it.
- Then: local `products` lookup → Open Food Facts if enabled and not cached
  → result view. A progress indicator with a `Cancel` action covers the fetch.
- On `OffTransient` a retry banner is offered rather than an "unknown product"
  claim [R6.1].

---

## 4. Camera — ingredient list (OCR)

```
┌────────────────────────────────────────┐
│ ← Scan ingredient list                 │
├────────────────────────────────────────┤
│                                        │
│   Take a photo of the ingredient list. │
│                                        │
│   For a good result:                   │
│    • fill the frame with the list      │
│    • hold the camera parallel          │
│    • avoid glare and shadows           │
│                                        │
│         [ 📷  Take photo ]             │
│         [ 🖼  Pick an image ]          │
│                                        │
│   You can correct the recognised text  │
│   before it is checked.                │
└────────────────────────────────────────┘

        ↓ system camera UI ↓  ↓ recognising… ↓  → §5 review
```

**Behaviour**

- Android/iOS only [§3]. Route not registered elsewhere.
- The **system camera UI** takes the photo (no in-app live preview, no frame
  streaming — see ARCHITECTURE decision 5.4); the returned image goes through
  on-device recognition and lands in §5.
- The photo is a temporary file, deleted right after recognition; no image is
  ever stored or uploaded [N10].
- Recognition producing no text goes to §5 with an empty field and a hint, not
  to an error dialog.
- A busy indicator with `Cancel` covers recognition.

---

## 5. OCR review / manual text entry

```
┌────────────────────────────────────────┐
│ ← Check ingredient text                │
├────────────────────────────────────────┤
│  Recognised text — correct it if needed│
│  ┌──────────────────────────────────┐  │
│  │ sugar, cocoa butter, HAZELNUTS,  │  │
│  │ skimmed milk powder, soy         │  │
│  │ lecithin (E322), natural         │  │
│  │ vanilla flavouring               │  │
│  │                                  │  │
│  └──────────────────────────────────┘  │
│  ⌸ Re-scan          ⎘ Paste            │
│                                        │
│           [    Check    ]              │
└────────────────────────────────────────┘
```

**Behaviour**

- The field is always editable before evaluation [R7.3]; this is the fix path
  for recognition errors, not a re-scan.
- Multiline, grows to 16 lines, keyboard `newline` action. Pasting uses the
  platform's own text selection controls — there is no separate paste button.
- `Check` is disabled while the field is empty.
- The same screen serves manual text entry (§6): it is entered with an empty
  initial text, which also selects the recorded input mode (`manualText`
  instead of `ocr`) and hides `Re-scan`.

---

## 6. Manual entry

```
┌────────────────────────────────────────┐
│ ← Enter manually                       │
├────────────────────────────────────────┤
│  ( ) Barcode        (•) Ingredient text│
│                                        │
│  ┌──────────────────────────────────┐  │
│  │ 4001234567890                    │  │
│  └──────────────────────────────────┘  │
│  Digits only, 8–14 characters          │
│                                        │
│           [    Look up    ]            │
└────────────────────────────────────────┘
```

**Behaviour**

- Always available [R3.1]; the default segment is *Barcode* where a camera
  exists (a manual entry is then usually a barcode the scanner could not read)
  and *Ingredient text* where it does not.
- Barcode field: numeric keyboard, validated to 8–14 digits, checksum **not**
  validated (labels are sometimes mis-typed by the user on purpose).
- *Ingredient text* switches to the §5 layout.

---

## 7. Result

Reached from every scan path and from History; identical widget in both
[see ARCHITECTURE §5].

### Mobile — `hit`

```
┌────────────────────────────────────────┐
│ ← Result                          [⋮] │
├────────────────────────────────────────┤
│ ┌────────────────────────────────────┐ │
│ │ ⚠  CONTAINS TERMS FROM YOUR LIST   │ │
│ │    2 matches                       │ │
│ └────────────────────────────────────┘ │
│                                        │
│ Choco Bar · Sweetco · 200 g            │
│ Open Food Facts, fetched 20 Aug 2026   │
│                                        │
│ Matches                                │
│ ─────────────────────────────────────  │
│ hazelnut                               │
│   "…cocoa butter HAZELNUTS skimmed…"   │
│ milk                                   │
│   "…skimmed MILK powder soy…"          │
│                                        │
│ Declared by Open Food Facts            │
│  [nuts] [milk] [soy]                   │
│ May contain                            │
│  [gluten]                              │
│                                        │
│ ▸ Evaluated text                       │
│                                        │
│ This is a text match, not a safety     │
│ assessment. Always read the packaging. │
│                                        │
│ [ Correct product data ]  [ Re-scan ]  │
└────────────────────────────────────────┘
```

### Mobile — `noMatch` / `unknown` banners

```
┌────────────────────────────────────────┐   ┌────────────────────────────────┐
│ ✓  NO TERM FROM YOUR LIST FOUND        │   │ ?  COULD NOT BE CHECKED        │
│    Checked 7 terms against the         │   │    This barcode is not in Open │
│    ingredient text                     │   │    Food Facts.                 │
└────────────────────────────────────────┘   │  [Scan ingredient list]        │
                                             │  [Enter text manually]         │
                                             └────────────────────────────────┘
```

### Desktop

Two columns: verdict banner + matches on the left, product data, tags and the
evaluated text on the right; action buttons in the app bar.

**Behaviour**

- Verdict is carried by text **and** colour, never colour alone [R7.4, N9]:
  `hit` → `colorScheme.error`, `noMatch` → semantic green,
  `unknown` → neutral surface.
- `noMatch` wording never says "safe" or "free from" [R5.6 table].
- Every match shows surrounding context so a false positive is recognisable
  [R5.6].
- Source line states provenance: `Open Food Facts, fetched <date>` /
  `Corrected by you` / `Recognised text` / `Typed text` [R7.5].
- `Declared by` = `allergensTags`, `May contain` = `tracesTags` — displayed,
  **not** matched [§5.4].
- `▸ Evaluated text` expands the exact text that was matched.
- Buttons: *Correct product data* (barcode scans only) and *New scan*.
- `⋮`: *Share result as text* — which includes the disclaimer line — and
  *Delete this scan*. Pre-filling a new term from a text selection is a
  planned addition, not implemented.
- The scan is already persisted when this screen opens [R7.7]; navigating back
  keeps it in History.
- With an empty allergy list: `unknown`, and the banner links to Allergies
  [R5.7].

---

## 8. Product correction

```
┌────────────────────────────────────────┐
│ ← Correct product data          [Save] │
├────────────────────────────────────────┤
│ Barcode 4001234567890                  │
│                                        │
│ Product name                           │
│ ┌──────────────────────────────────┐   │
│ │ Choco Bar                        │   │
│ └──────────────────────────────────┘   │
│ Brand                    Quantity      │
│ ┌───────────────┐  ┌───────────────┐   │
│ │ Sweetco       │  │ 200 g         │   │
│ └───────────────┘  └───────────────┘   │
│ Ingredient text                        │
│ ┌──────────────────────────────────┐   │
│ │ sugar, cocoa butter, hazelnuts,  │   │
│ │ …                                │   │
│ └──────────────────────────────────┘   │
│ ⌸ Scan ingredient list into this field │
│                                        │
│ ⓘ Your corrections are kept locally    │
│   and are never overwritten by a       │
│   later lookup.                        │
└────────────────────────────────────────┘
```

**Behaviour**

- `Save` sets `hasManualOverride = true`, leaves `source` untouched [R4.6],
  and re-evaluates the current scan immediately.
- Nothing is sent to Open Food Facts [§1.2].
- If a later fetch returns different remote data, the user is *asked* rather
  than overwritten [R4.4].

---

## 9. Allergies

### Mobile

```
┌────────────────────────────────────────┐
│ My allergy terms                  [🔍] │
├────────────────────────────────────────┤
│  ACTIVE (7)                            │
│  ─────────────────────────────────────  │
│  hazelnut                        [●]   │
│  milk                            [●]   │
│  soy lecithin                    [●]   │
│    severe                              │
│  …                                     │
│                                        │
│  INACTIVE (2)                          │
│  ─────────────────────────────────────  │
│  celery                          [○]   │
│                                        │
│                              ( + )     │
├────────────────────────────────────────┤
│  Scan  [Allergies]  History  Settings  │
└────────────────────────────────────────┘
```

### Add / edit screen

Implemented as a route (`/allergies/add`, `/allergies/:termId/edit`) rather than
a modal sheet, so the route tree in `doc/CLASS_DIAGRAM.md` is the whole
navigation story and a deep link can reach it.

```
┌────────────────────────────────────────┐
│ ← Add a term                           │
│  ┌──────────────────────────────────┐  │
│  │ hazelnut                         │  │
│  └──────────────────────────────────┘  │
│  At least 3 characters                 │
│  Note (optional)                       │
│  ┌──────────────────────────────────┐  │
│  │ severe                           │  │
│  └──────────────────────────────────┘  │
│  ⓘ Only this exact word is searched.   │
│    Add "corylus avellana" or "E322"    │
│    as separate terms if you need them. │
│                                        │
│         [Cancel]        [Save]         │
└────────────────────────────────────────┘
```

**Behaviour**

- Active first, then inactive; each group alphabetical [R7.8].
- Toggle switches `isActive` without deleting [§4.1].
- Swipe-to-delete with an undo snackbar; deleting never touches history
  [R7.9].
- Duplicate rejected by normalised form, naming the existing entry [R4.1].
- Under 3 normalised characters → `Save` stays disabled [R4.2/R5.5].
- The ⓘ note is required copy, not decoration — it is the user-facing form of
  the §5.4 limitation.
- Empty state: explanatory text + a prominent `Add your first term`.

---

## 10. History

```
┌────────────────────────────────────────┐
│ History                     [Filter ▾] │
├────────────────────────────────────────┤
│  TODAY                                 │
│  ⚠ Choco Bar 200g                14:02 │
│     2 matches · barcode                │
│  ✓ text scan                     09:11 │
│     0 matches · recognised text        │
│                                        │
│  19 AUG 2026                           │
│  ? 4001234567890                 18:40 │
│     not found · barcode                │
│                                        │
│  Keeping the last 500 scans            │
├────────────────────────────────────────┤
│  Scan  Allergies  [History]  Settings  │
└────────────────────────────────────────┘
```

**Behaviour**

- Reverse chronological, grouped by day; filter by verdict [R7.10].
- Opens the stored result view with **no** network access — `evaluatedText`,
  `productNameSnapshot` and `termSnapshot` make each entry self-contained
  [R4.7].
- Swipe-to-delete a single entry; app-bar overflow offers `Clear history`
  behind a confirmation.
- The retention line states the cap of 500 [R4.8].
- Desktop: master/detail — list left, result right.

---

## 11. Settings

```
┌────────────────────────────────────────┐
│ Settings                               │
├────────────────────────────────────────┤
│  APPEARANCE                            │
│   Theme                     System ▾   │
│                                        │
│  SCANNING                              │
│   Preferred ingredient language        │
│                            English ▾   │
│   Look up products online       [●]    │
│     Off = no network requests at all   │
│                                        │
│  DATA                                  │
│   Local backup                     ›   │
│   Nextcloud sync            Not set ›  │
│                                        │
│  ABOUT                                 │
│   About AllergyScanner             ›   │
│   Privacy                          ›   │
│   App logs                         ›   │
└────────────────────────────────────────┘
```

**Behaviour**

- Every switch writes through a targeted DAO update, never a whole cached
  settings object [house rule 7].
- `Look up products online` off → the Open Food Facts service is not called at
  all [R6.6]; the barcode flow then resolves only locally.
- Sub-screens: **Local backup** (export ZIP / import ZIP, last export time),
  **Nextcloud sync** (URL, user, password, certificate fingerprint, test
  connection, sync now, `lastSyncAt`), **About** (version, GPL-3.0 notice, the
  §1 disclaimer, link to logs), **Privacy** (mirrors `PRIVACY.md`), **App
  logs** (viewer with share and clear) [R7.11].

---

## 12. Screen flow summary

```
first launch ─► Disclaimer gate (inside the shell) ─► shell content

shell
├── Scan ──┬─► Camera barcode ──┬─► Result ─┬─► Product correction ─┐
│          │                    │           └─► (back to Scan)      │
│          │                    └─► (unknown) ─► Photo OCR / Manual  │
│          ├─► Photo OCR ─► Text review ─► Result                    │
│          └─► Manual entry ──┬─► (barcode)  ─► Result               │
│                             └─► (text) ─► Text review ─► Result    │
├── Allergies ─► Add / edit screen                                   │
├── History ─► Result (stored, offline) ──────────────────────────────┘
└── Settings ─┬─► Local backup
              ├─► Nextcloud sync
              ├─► About ─┬─► App logs
              │          ├─► Privacy
              │          └─► Open source licences
              └─► App logs / Privacy
```

Typed text and recognised text meet at the **Text review** screen, so both
reach the pipeline through exactly one path.

Tab state survives switching (`StatefulShellRoute.indexedStack`), so leaving a
half-typed manual entry for the Allergies tab and coming back preserves it.
