# AllergyScanner

Scan a product's barcode or photograph its ingredient list, and check it
against your own list of allergy-relevant substances — offline, without an
account.

> **This is not a medical device.** AllergyScanner matches text against the
> terms you enter. It does not decide whether a product is safe for you to eat.
> Product data comes from the crowd-sourced Open Food Facts database and is not
> verified; recognised text can be wrong; only the exact words you list are
> found, not their synonyms. Always read the packaging.

**Status: builds and passes its tests on the host toolchain; not yet verified
on a device.** As of 2026-10-01, `flutter pub get`, `build_runner`,
`flutter analyze --fatal-infos` and `flutter test` (193 tests) are all green on
Flutter 3.47.1 / Dart 3.13.1. What has **not** been verified is any real
Android or iOS device or emulator build, so the camera, on-device text
recognition and WebDAV paths are written and specified but never executed on
real hardware; CI's Android and iOS jobs are the next gate. Generated code
(`*.g.dart`, `app_localizations*.dart`) and the `android/`/`ios/` folders are
not committed — see "Getting started" for the two commands that produce them.

---

## Features

**Checking a product**

- Scan a barcode with the camera and look the product up in Open Food Facts.
- Photograph the ingredient list and read it with on-device text recognition.
- Type or paste a barcode or an ingredient list on any platform.
- Recognised text is narrowed to the ingredients section when a localized
  "Ingredients:" marker is found (DE/EN/FR/IT), so the rest of the packaging
  cannot produce a false match; you always see and can edit the text before
  it is checked.
- A clear verdict: *contains terms from your list* / *no term found* /
  *could not be checked* — with every match shown in its surrounding text.

**Your allergy list**

- Free-text terms, matched case- and accent-insensitively.
- Terms can be deactivated without deleting them.
- Notes per term.
- Group related terms (e.g. the same allergen in different languages), with
  an optional color and a plain Low/Medium/High criticality tag — visual
  organisation only, never a safety assessment.
- Optional translation *suggestions* when adding names to a group (MyMemory,
  keyless, DE/EN/ES/FR/IT/NO/SV) — nothing is ever added without your
  review, and it is off whenever online lookup is off.
- Export or import just the allergy list as a shareable JSON file (e.g. for
  a caregiver or a school) — separate from, and in addition to, the full
  ZIP backup below; import always merges, never replaces.

**History**

- Every check is stored with the exact text it evaluated, so past results stay
  readable offline even after a term is deleted or a product is corrected.
- Add a name, a shop and a photo to an entry after the fact — the photo is
  kept on your device until you remove it, and adding any of them never
  re-evaluates the stored verdict.
- Entries are grouped by shop automatically, each group ordered by its own
  most recent check.
- Last 500 checks, filterable by verdict.

**Your data**

- Correct or complete a product locally; your correction is never overwritten
  by a later lookup.
- ZIP export and import of everything the app stores.
- Optional Nextcloud/WebDAV sync of that archive; the password lives in the
  platform key store.
- Everything works with no network at all — online lookup can be switched off
  entirely.
- The app's own UI can be switched between English and German in Settings,
  independent of the ingredient-language preference above; it follows the
  device language by default.

Not included: accounts, telemetry, notifications, nutrition or diet
evaluation, AI interpretation of ingredient lists, and writing back to Open
Food Facts. See `doc/REQUIREMENTS.md` §1.2.

---

## Platforms

**Android and iOS**, each with a debug and a release artifact. Both have the
full feature set.

| Platform | Artifact (debug and release) | Note |
|---|---|---|
| Android | `.apk` | Signed with the release key when the keystore secrets are configured, otherwise with the debug key |
| iOS | `.zip` of `Runner.app` | **Unsigned** — CI has no provisioning profile, so the artifact is not installable without re-signing. It proves the target compiles |

**macOS, Windows and Linux are not supported.**
`google_mlkit_text_recognition` covers no desktop platform, and
`mobile_scanner` covers only macOS — so Linux and Windows would have neither
scanning feature and macOS would have barcode scanning without ingredient-list
recognition. v0.1 is mobile-only rather than partially working on three more
platforms. Adding one back needs a desktop OCR backend and, for Windows and
Linux, a desktop barcode input path; both are planned features, not silent gaps
(`doc/REQUIREMENTS.md` §11).

The layout is still adaptive at 600 dp — that is for tablets and landscape
phones, not for a desktop target.

Verified on pub.dev, 2026-08-20: `mobile_scanner` 7.4.0 supports Android, iOS
and macOS; `google_mlkit_text_recognition` 0.17.1 supports Android and iOS only.

---

## Tech stack

| Concern | Library |
|---|---|
| UI | Flutter, Material 3 (indigo seed, system dark mode) |
| Localization | `flutter_localizations` + `intl`, English/German (`flutter gen-l10n`) |
| State | `flutter_riverpod` (manual providers) |
| Navigation | `go_router` (`StatefulShellRoute.indexedStack`) |
| Database | `drift` + `drift_flutter` + `path_provider` |
| HTTP | `dio` |
| Barcode | `mobile_scanner` |
| Text recognition | `google_mlkit_text_recognition` (on-device) |
| Photo capture | `image_picker` |
| Secrets | `flutter_secure_storage` |
| Backup | `archive`, `file_picker`, `share_plus` |
| Utilities | `uuid`, `intl`, `crypto`, `equatable`, `package_info_plus`, `url_launcher` |

Exact version constraints are pinned in `src/pubspec.yaml`.

---

## Getting started

Prerequisites: Flutter stable ≥ 3.29 with Dart SDK `^3.7.0` (required by
`mobile_scanner` 7.x), Java 17 for Android builds, and Xcode 15.3+ for iOS.

The platform folders are not committed, so create the one you need first:

```bash
cd src
flutter create --platforms=android,ios .   # or just the one you build

flutter pub get
dart run build_runner build --delete-conflicting-outputs   # required — generates *.g.dart
flutter analyze --fatal-infos
flutter test
flutter run -d <device>
```

Building a release artifact locally:

```bash
cd src
flutter build apk --release              # Android
flutter build ios --release --no-codesign
```

### Open Food Facts

No API key and no account is needed. Two things are mandatory:

- a custom `User-Agent` of the form `AllergyScanner/<version> (<contact>)` on
  every request — Open Food Facts policy;
- respecting the documented read limit of 15 product requests per minute per IP.

Both live in `core/services/open_food_facts_service.dart`. Online lookup can be
switched off in Settings, after which the app makes no HTTP requests at all.

### Nextcloud sync (optional)

Settings → Nextcloud sync: base URL, username, app password. Self-signed
certificates are supported by pinning their SHA-256 fingerprint; a mismatch
rejects the connection. The password is stored in `flutter_secure_storage` and
never in the database, a log or a backup archive.

---

## CI/CD

Three workflows; `build.yml` is the only file that contains build steps.

| Workflow | Trigger | Contents |
|---|---|---|
| `build.yml` | `workflow_call` | 2 platforms × (debug, release) + CycloneDX SBOM |
| `ci.yml` | push to `main` / `develop` / `feature/**`, PRs to `main` / `develop` | `flutter analyze --fatal-infos` + `flutter test`, then `build.yml` with version `<pubspec>-dev` |
| `release.yml` | tag `v<major>.<minor>.<patch>` | the same gate, then `build.yml` with the tag version, then a GitHub Release with all artifacts attached |

Build number is always the GitHub run number. Debug artifacts are attached to
releases deliberately — they are what a user is asked to run when a release
build misbehaves.

Optional secrets; every one of them is absent-tolerant:

| Secret | Effect when set |
|---|---|
| `ANDROID_RELEASE_KEYSTORE_B64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` | Both APK build types are signed with the real release key |

Both build modes run for both supported platforms. macOS, Windows and Linux
have no jobs — see the Platforms section for why.

---

## Project structure

```
AllergyApp/
├── README.md
├── CLAUDE.md                 agent/developer orientation, conventions, traps
├── CONTRIBUTING.md
├── PRIVACY.md
├── LICENSE                   GPL-3.0
├── doc/
│   ├── REQUIREMENTS.md       numbered requirements, data model, matching rules
│   ├── ARCHITECTURE.md       layers, scan pipeline, key design decisions
│   ├── CLASS_DIAGRAM.md      provider graph, central type signatures, routes
│   └── SCREENS.md            ASCII wireframes, mobile + desktop, per screen
├── .github/workflows/        build.yml, ci.yml, release.yml
└── src/                      the Flutter project
```

Platform folders (`android/`, `ios/`) and generated `*.g.dart` files
are **not** committed; CI scaffolds and regenerates them, and every native
change (permissions, usage descriptions, entitlements, deployment targets) is a
patch step in `build.yml`.

---

## Documentation

- [`doc/REQUIREMENTS.md`](doc/REQUIREMENTS.md) — what the app must do, the data
  model, the matching rules and their accepted limitations.
- [`doc/ARCHITECTURE.md`](doc/ARCHITECTURE.md) — how it is built and why.
- [`doc/CLASS_DIAGRAM.md`](doc/CLASS_DIAGRAM.md) — provider graph and type
  signatures.
- [`doc/SCREENS.md`](doc/SCREENS.md) — wireframes and per-screen behaviour.
- [`CLAUDE.md`](CLAUDE.md) — commands, conventions and platform traps.
- [`PRIVACY.md`](PRIVACY.md) — what leaves the device, and when.

---

## Licence

GPL-3.0. Product data retrieved from Open Food Facts is licensed by them under
the Open Database License (ODbL); the app attributes it in the result view and
in the About screen.
