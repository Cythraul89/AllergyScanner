# Privacy — AllergyScanner

This document describes what AllergyScanner stores and what leaves the device.
The in-app privacy screen (Settings → Privacy) mirrors it.

Last updated: 2026-08-20. Applies to the specification; it must be re-checked
against the implementation before the first release.

---

## 1. No account, no telemetry

AllergyScanner has no user accounts, no registration and no login. It contains
no analytics, no crash-reporting service, no advertising and no tracking
identifiers. Nothing about your usage is collected.

## 2. What is stored on your device

In an SQLite database inside the app's private storage:

- your allergy terms, their notes and their active/inactive state;
- products you scanned — barcode, name, brand, quantity, ingredient text,
  allergen tags, image URL — as retrieved from Open Food Facts or as you
  corrected them;
- your scan history: time, input type, the ingredient text that was evaluated,
  the verdict and the matches (last 500 scans);
- your settings.

In the platform key store (`flutter_secure_storage`), only if you configure
Nextcloud sync: the WebDAV password. It is never written to the database, to a
log file or into a backup archive.

In a log file inside the app's private storage: diagnostic messages
(errors, network failures, backup results). You can view, share and clear it
under Settings → App logs. It contains no ingredient text and no credentials.

Uninstalling the app removes all of it.

## 3. What leaves the device

Exactly three things, all of them under your control:

| What | Sent to | When | Contains |
|---|---|---|---|
| The barcode digits | Open Food Facts (`world.openfoodfacts.org`) | Only when you scan or enter a barcode that is not already cached locally, and only while *Look up products online* is enabled | The barcode, plus the app's mandatory `User-Agent` (app name, version, contact address). No device identifier, no allergy terms, no history |
| A backup archive | Your own Nextcloud/WebDAV server | Only when you have configured sync, and only on app start or when you trigger it | Your allergy terms, products and scan history. No passwords |
| A shared file or text | Wherever you send it | Only when you use *Share* | The exported archive, log file or result text you chose to share |

Switching *Look up products online* off in Settings stops all HTTP requests to
Open Food Facts; the app then works purely from locally stored products.

## 4. Camera and photos

- The camera is used only while a scan screen is open, and the permission is
  requested at that moment, not at app start.
- Barcode detection and ingredient-text recognition both run **on the device**.
  No image is sent anywhere.
- A photo taken for text recognition is written to a temporary file, processed,
  and deleted immediately afterwards. No photo is added to your gallery and none
  is stored by the app.
- Only the recognised text — which you can edit before checking — is stored, as
  part of the scan history.

## 5. Your allergy terms

Your allergy terms and your scan history never leave the device except inside a
backup archive you export or sync to your own server. They are never sent to
Open Food Facts or to any other third party.

## 6. Third-party services

| Service | Role | Data received | Terms |
|---|---|---|---|
| Open Food Facts | Product database | Barcode, `User-Agent` | Their privacy policy applies to their servers; product data is licensed under the ODbL |
| Google ML Kit (text recognition) | On-device text recognition | Nothing — the bundled model runs locally | No network access is used by this component |
| Your Nextcloud/WebDAV server | Optional backup target | The backup archive | Yours |

Google ML Kit's text recognition is used in its on-device form. If a future
version were to use a cloud model, that would be a change to this document and
would be opt-in.

## 7. Children

The app is not directed at children and collects nothing that would identify
anyone.

## 8. Your control

- Delete a single scan, clear the whole history, or delete any allergy term at
  any time.
- Export everything as a ZIP archive, or delete the app to remove all data.
- Disable online lookup entirely.
- Remove the sync configuration, which also deletes the stored password.

## 9. Not a medical device

AllergyScanner performs text matching on data it cannot verify. It does not
determine whether a product is safe for you. Always read the packaging.

## 10. Contact

Issues and questions: the repository's issue tracker. The contact address used
in the Open Food Facts `User-Agent` is stated in the About screen.
