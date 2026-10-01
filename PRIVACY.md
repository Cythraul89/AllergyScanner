# Privacy — AllergyScanner

This document describes what AllergyScanner stores and what leaves the device.
The in-app privacy screen (Settings → Privacy) mirrors it.

Last updated: 2026-10-01, re-checked against the implementation. It must be
re-checked again before the first release, once the app has run on a real
device.

---

## 1. No account, no telemetry

AllergyScanner has no user accounts, no registration and no login. It contains
no analytics, no crash-reporting service, no advertising and no tracking
identifiers. Nothing about your usage is collected.

## 2. What is stored on your device

In an SQLite database inside the app's private storage:

- your allergy terms, their notes and their active/inactive state, optionally
  organised into groups (several names for the same allergen, e.g. across
  languages);
- products you scanned — barcode, name, brand, quantity, ingredient text,
  allergen tags, image URL — as retrieved from Open Food Facts or as you
  corrected them;
- your scan history: time, input type, the ingredient text that was evaluated,
  the verdict and the matches (last 500 scans), plus, if you chose to add
  them, a name, a shop and a photo you attached to that entry — kept
  on-device until you remove it or delete the scan (§4);
- your settings.

In the platform key store (`flutter_secure_storage`), only if you configure
Nextcloud sync: the WebDAV password. It is never written to the database, to a
log file or into a backup archive.

In a log file inside the app's private storage: diagnostic messages
(errors, network failures, backup results). You can view, share and clear it
under Settings → App logs. Because it is shareable, it deliberately contains
none of your own text: no ingredient text, no allergy terms or group names,
and no credentials.

Uninstalling the app removes all of it.

## 3. What leaves the device

Exactly five things, all of them under your control:

| What | Sent to | When | Contains |
|---|---|---|---|
| The barcode digits | Open Food Facts (`world.openfoodfacts.org`) | Only when you scan or enter a barcode that is not already cached locally, and only while *Look up products online* is enabled | The barcode, plus the app's mandatory `User-Agent` (app name, version, contact address). No device identifier, no allergy terms, no history |
| A name you type when adding to an allergen group | MyMemory (`api.mymemory.translated.net`) | Only when you tap *Suggest translations*, and only while *Look up products online* is enabled | The name you typed, plus an optional contact address. Nothing else about your allergy list, history or device |
| A backup archive | Your own Nextcloud/WebDAV server | Only when you have configured sync, and only on app start or when you trigger it | Your allergy terms and the groups they are organised into, the products you scanned and your scan history — including any photo you attached to a history entry. No passwords |
| An allergy-list JSON file | Wherever you send it | Only when you use *Export as JSON* on the Allergies screen | Your full list of allergen groups and terms — including each group's colour and criticality tag, and each term's note. No history, no products, no settings, no passwords |
| A shared file or text | Wherever you send it | Only when you use *Share* | The exported archive, log file or result text you chose to share |

Switching *Look up products online* off in Settings stops all HTTP requests to
both Open Food Facts and MyMemory; the app then works purely from locally
stored products, and translation suggestions are unavailable.

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
- **Separately, and only if you choose to**: you can attach a photo to a
  history entry after the fact (*Edit details*, e.g. a photo of the receipt
  or shelf). Unlike the scanning photo above, this one **is** stored
  on-device, in the app's private storage, until you remove it or delete the
  scan it belongs to. It is never uploaded on its own — it only leaves the
  device inside a backup archive you explicitly export or sync (§3).

## 5. Your allergy terms

Nothing is ever sent anywhere automatically. Your allergy terms leave the
device only in these three cases, each of which you trigger yourself:

- inside a backup archive you export or sync to your own server (§3);
- inside an allergy-list JSON file you export and share (§3) — this one
  carries your full list of groups and terms;
- a **single** group name you type, when you tap *Suggest translations*, sent
  to MyMemory and nowhere else (§3, §6).

Your scan history leaves the device only inside a backup archive you export or
sync, or in a single result text you choose to share (§3). It is never sent to
Open Food Facts, to MyMemory, or to any other third party, and neither your
terms nor your history are ever sent for analytics, advertising or profiling —
there is none of that in this app (§1).

## 6. Third-party services

| Service | Role | Data received | Terms |
|---|---|---|---|
| Open Food Facts | Product database | Barcode, `User-Agent` | Their privacy policy applies to their servers; product data is licensed under the ODbL |
| MyMemory | Translation suggestions for allergen group names | The name you typed, an optional contact address | Their privacy policy applies; used only to *suggest* a translation you review before it becomes a term |
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
- Remove a photo you attached to a history entry independently of deleting
  the whole scan.
- Export everything as a ZIP archive, or export just your allergy list as a
  JSON file, or delete the app to remove all data.
- Disable online lookup entirely, which also disables translation
  suggestions.
- Remove the sync configuration, which also deletes the stored password.

## 9. Not a medical device

AllergyScanner performs text matching on data it cannot verify. It does not
determine whether a product is safe for you. Always read the packaging.

## 10. Contact

Issues and questions: the repository's issue tracker. The contact address used
in the Open Food Facts `User-Agent` is stated in the About screen.
