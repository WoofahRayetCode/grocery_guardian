## Grocery Guardian

Grocery Guardian is a Flutter app that helps you scan products, spot allergens, and find safer alternatives. It uses community data from Open Food Facts and Open Beauty Facts and adds simple safety advisories for babies and maternity.

### Features

- Barcode scanning with robust EAN/UPC handling
- Product lookup via Open Food Facts (foods) and Open Beauty Facts (cosmetics)
- Allergen detection and “Discomfort” tagging, with per-profile preferences and a “My allergy items” screen
- Mothers/babies safety advisories for foods and cosmetics (heuristic, conservative)
- Usage hints for cosmetics (Leave-on vs Rinse-off) and EU-26 fragrance allergen flags
- Alternative suggestions and not-found fallback to name search
- Local caching of lookups (7-day TTL) with cache clearing
- Modern Material 3 UI with consistent chip styling and improved contrast
- Ads/donations via compile-time flags; Play flavor enables ads and hides donations
- Android product flavors (play/oss) with distinct app IDs, names, and icons
- Linux helper scripts for fast device-first build/deploy (USB or wireless ADB)
- Tests validating advisory heuristics; attributions for OFF/OBF in-app and README

### Screenshots

*(Adding soon)*

### Getting Started

1. Clone the repo:
   ```sh
   git clone https://github.com/WoofahRayetCode/grocery_guardian.git
   ```
2. Install dependencies:
   ```sh
   flutter pub get
   ```
3. Run the app:
   ```sh
   flutter run
   ```

### Linux helper scripts

- Debug (fresh clean + run on device if present, else Linux desktop):
  ```sh
  bash ./debug_build_fresh.sh
  ```
- Release (fresh clean + build APK + install if device present):
  ```sh
  bash ./release_build_fresh.sh
  ```

### Play Store build

- Build an App Bundle with Google Play ads enabled and donations disabled:
  ```sh
  bash ./play_build.sh
  ```
  Optional: provide your banner Ad Unit ID
  ```sh
  ADMOB_BANNER_ANDROID_ID="ca-app-pub-xxxxxxxxxxxxxxxx/xxxxxxxxxx" bash ./play_build.sh
  ```
  Notes:
  - Uses Android product flavor `play` with its own app name, icon, and appId (`.play`) for side-by-side installs.
  - OSS/dev builds can use flavor `oss`.

### Versioning

- Release builds: versionName is the compile date (YYYY.MM.DD) and versionCode is YYYYMMDD.
- Debug builds: versionName includes the exact compile time in UTC (YYYY.MM.DD HH:mm:ss UTC); versionCode is YYYYMMDD.

Notes:
- The version code must monotonically increase for Play Store updates; a new build on a later date will naturally increment it.
- The base pubspec `version:` is ignored for Android versioning by the Gradle variant logic.

### Permissions

This project requests a minimal set of permissions:

- Camera: required for barcode scanning when you choose to scan
- Internet + Network state: fetch product data (OFF/OBF) and load ads in the Play build
- Google Advertising ID (Play flavor): required by Google Mobile Ads SDK

Notes:
- No storage, contacts, location, or SMS permissions are requested.
- Install-from-unknown-sources is explicitly removed to avoid unnecessary prompts.

---

**Grocery Guardian** is open source and welcomes contributions and suggestions!

---

### Data sources & attribution

- Open Food Facts (world.openfoodfacts.org) — Community-driven product and nutrition data. Licensed under CC-BY-SA. Please consider contributing corrections and new products back to OFF.
- Open Beauty Facts (world.openbeautyfacts.org) — Community-driven cosmetics/personal care product data. Licensed under ODbL/CC-BY-SA. Please consider contributing missing products.

This app displays and normalizes public data from these projects. Trademarks and data belong to their respective owners.

---

© 2025 WoofahRayetCode. All rights reserved.