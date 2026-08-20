# Contributing to AllergyScanner

---

## Branches

| Branch | Purpose |
|---|---|
| `main` | Released state. Never pushed to directly. |
| `develop` | Integration branch. Pull requests target this. |
| `feature/<name>` | One change per branch, branched from `develop`. |

A release is made by pushing a `v<major>.<minor>.<patch>` tag on `main`, which
triggers `release.yml`.

---

## Setup

```bash
git clone <repository-url>
cd AllergyApp/src
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter test
```

Android builds need Java 17; iOS builds need Xcode 15.3+ with an iOS 15.5
deployment target.

The platform folders are not committed. `flutter run` needs the one for your
device, so create it locally — it is git-ignored:

```bash
cd src
flutter create --platforms=android,ios .
```

Only Android and iOS are supported; `macos/`, `linux/`, `windows/` and `web/`
are git-ignored on purpose (see `doc/REQUIREMENTS.md` §3).

Native changes (permissions, `Info.plist` usage descriptions, entitlements,
deployment targets) must **not** be committed in those folders. They belong in
`.github/workflows/build.yml` as a patch step, so CI and local builds agree.

---

## Code generation

`*.g.dart` files are generated and not committed. After any change under
`src/lib/core/database/tables/` or `.../daos/`:

```bash
cd src
dart run build_runner build --delete-conflicting-outputs
```

Never hand-edit a generated file.

---

## Before opening a pull request

```bash
cd src
dart format .
flutter analyze --fatal-infos    # must be clean; no // ignore to get there
flutter test                     # must pass
```

`--fatal-infos` is the gate in CI too. If a finding comes from an SDK version
difference rather than from the code, say so in the PR instead of suppressing
it.

---

## Commit messages

- Imperative mood: "Add barcode retry banner", not "Added" or "Adds".
- First line under 72 characters, no trailing period.
- Body explains *why* when it is not obvious from the diff.
- Reference issues as `Fixes #42`.

---

## Recipes

### Adding a Drift table

1. Create `src/lib/core/database/tables/<name>_table.dart` — extend `Table`,
   annotate `@DataClassName('<Name>Row')`.
2. Register it in `@DriftDatabase(tables: [...])`.
3. Create `src/lib/core/database/daos/<name>_dao.dart` with `@DriftAccessor`.
4. Add the DAO to `@DriftDatabase(daos: [...])` and expose a getter on
   `AppDatabase`.
5. Bump `schemaVersion` and add the `if (from < N) { ... }` block in
   `onUpgrade`.
6. Run `dart run build_runner build --delete-conflicting-outputs`.
7. Extend the in-memory DAO test for the new queries, including foreign-key
   behaviour.

### Changing the text normalisation rules

This is the one change that can silently break matching, because
`allergen_terms.normalizedTerm` is a stored column
(`doc/ARCHITECTURE.md` §5.2).

1. Change `TextNormalizer.normalize` and its unit tests together.
2. Bump `schemaVersion` and add a migration step that **recomputes
   `normalizedTerm` for every existing row**.
3. Check the uniqueness constraint still holds after recomputation — two terms
   may now normalise to the same value; the migration has to resolve that, not
   crash.
4. Add a test that the migration converts a realistic old row correctly.

### Adding a feature

1. `src/lib/features/<feature>/` with `<feature>_screen.dart` and
   `<feature>_provider.dart`.
2. Read-side providers first (`StreamProvider`/`FutureProvider`), then one
   `…Actions` class exposed through a `Provider` for mutations.
3. Route it inside the shell branch it belongs to, in `app.dart`.
4. Tests for the pure parts; a widget test only where the widget has real
   logic.
5. Update `doc/REQUIREMENTS.md`, `doc/SCREENS.md`, `doc/CLASS_DIAGRAM.md` and
   the layout tree in `CLAUDE.md` in the same commit.

### Adding a platform-dependent capability

Extend `ScanCapabilities` (`core/utils/scan_capabilities.dart`) and register the
route conditionally in `routerProvider`. Do not add a `Platform.isAndroid` check
inside a widget — see `doc/ARCHITECTURE.md` §5.8.

### Adding a platform

Both scanning features must work there first (`doc/REQUIREMENTS.md` §11), then:
add the job to `build.yml` with its native patch steps, extend
`ScanCapabilities`, un-ignore the platform folder pattern in `.gitignore`, and
update the platform tables in the README, `CLAUDE.md` and
`doc/REQUIREMENTS.md` §3 in the same commit.

---

## Code style

- English everywhere: code, comments, identifiers, documentation, commit
  messages.
- No abbreviations in identifiers. `context`, not `ctx`; `error`, not `err`.
  Established technical terms (`url`, `id`, `http`, `json`, `api`, `ocr`) are
  fine.
- Comments explain *why*. If the code already says it, leave it out.
- State management: Riverpod 2 with manual providers, no code generation, no
  service locator, no global singletons. Services are constructor-injected and
  overridden in `ProviderScope`.
- Read side and write side are separate providers. Widgets `watch` reads and
  `read` actions.
- Writes are column-scoped DAO methods. Never persist a whole object that came
  out of a cached provider.
- Domain models are immutable (`const` constructor, `final` fields,
  `copyWith`, `Equatable`); Drift `*Row` classes never leave the DAO layer.
- Calculators are pure and static: no I/O, no logging, no `DateTime.now()`
  inside — pass the time in.
- Services never show UI and never throw for an expected outcome; they return a
  sealed result.
- Everything logs through `LogService`. `print` is not used.
- Imports inside `lib/` are relative.
- Keep changes surgical: no drive-by reformatting, no unrequested abstraction.

---

## Pull request checklist

- [ ] `dart format .` applied
- [ ] `flutter analyze --fatal-infos` clean, with no new `// ignore`
- [ ] `flutter test` passes
- [ ] `build_runner` re-run if any Drift file changed, and `schemaVersion`
      bumped with a migration step if the schema changed
- [ ] New behaviour covered by a test; matching-rule changes covered rule by
      rule
- [ ] Docs updated in the same commit (`doc/*`, `CLAUDE.md`)
- [ ] A newly discovered platform trap added to the "Platform traps" section of
      `CLAUDE.md`
- [ ] No credential, token or personal data added to the repository, a log or a
      backup archive
- [ ] Wording of any user-facing verdict text checked against
      `doc/REQUIREMENTS.md` §5.6 — the app never claims a product is safe
