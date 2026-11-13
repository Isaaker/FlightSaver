# Changelog

All notable user-facing changes to FlightSaver are documented here.

## 1.1.1 — 2026-11-13

- Added a repository contact URL to the shared application User-Agent so Planespotters can identify and contact the maintainer.
- Centralised the User-Agent used by ADS-B, map and photo clients.
- Kept registration as the primary Planespotters lookup and ICAO hex as fallback, including after HTTP 403 and other non-rate-limit registration failures.
- Preserved a separate backoff path for HTTP 429 responses.
- Added repository documentation, contribution guidance, privacy and security policies, offline source-contract tests and GitHub Actions workflows.
- Changed the Screen Saver bundle identifier to `com.isaaker.flightsaver`, aligned the preferences identifier and added a one-time migration from the previous `com.local.FlightSaver` preferences domain.

## 1.1.0 — 2026-11-13

- Enlarged the featured-aircraft card and adjusted its layout to prevent text overflow.
- Removed the date and clock overlay because macOS already provides system time.
- Added Planespotters aircraft photographs, photographer credit and a link to the original photo page.
- Added registration-first photo search with ICAO hex fallback.
- Made OpenStreetMap the default no-key dark map option and retained CARTO as an optional provider with OpenStreetMap fallback.
- Added local map-tile caching and improved map attribution.

## 1.0.0 — Initial native screen saver

- Introduced the native AppKit / ScreenSaver implementation.
- Added ADS-B traffic display, aircraft labels, map rendering and screen saver preferences.
