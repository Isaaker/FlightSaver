# FlightSaver

[Read this in Spanish](README.es.md).

A native macOS screen saver that visualises nearby ADS-B traffic over a dark map, with an aviation-style heads-up display and an aircraft details card.

FlightSaver is built with Swift, AppKit and `ScreenSaver.framework`. It does not embed a browser, WebView or JavaScript runtime.

> **Status:** community project. FlightSaver is not an air traffic control tool, a navigation aid, or a certified aviation product. It must not be used for real-world flight operations.

## Features

- Live aircraft positions from public ADS-B data feeds, with automatic provider fallback.
- Dark OpenStreetMap-based map by default; optional CARTO Dark Matter tiles when you supply a CARTO key.
- Aircraft symbols, callsigns, altitude, speed, type, military/emergency indicators and motion trails.
- Distance rings in nautical miles, a configurable centre point and a traffic summary.
- A larger featured-aircraft card with registration, type, altitude, speed, vertical rate, track, range and bearing.
- Aircraft photographs from Planespotters.net when a matching photo is available. FlightSaver searches by registration first and ICAO 24-bit hex as fallback, credits the photographer and links to the original photo page.
- No clock or date overlay; macOS already provides system time in the screen saver experience.
- Local caching for map tiles and photo lookup metadata.

## Requirements

- macOS 12 Monterey or newer.
- Apple Silicon (`arm64`) or Intel (`x86_64`) Mac.
- Xcode Command Line Tools, providing `swiftc`, `codesign` and the macOS SDK.
- An internet connection for live traffic, map tiles and aircraft photographs.

There are no third-party Swift package dependencies.

## Build and install

Clone the repository and build on the Mac where you intend to run the screen saver:

```bash
git clone https://github.com/Isaaker/FlightSaver.git
cd FlightSaver
xcode-select --install   # only if Command Line Tools are not installed
./build.sh
```

The compiled bundle is created at `build/FlightSaver.saver`.

To install it for the current macOS user:

```bash
./build.sh --install
```

Then open **System Settings → Wallpaper → Screen Saver** (wording may vary by macOS version) and select **FlightSaver**. Open its **Options** panel to configure the map centre and display.

To cross-compile for a supported architecture on a compatible macOS SDK, set `ARCH` explicitly:

```bash
ARCH=arm64 ./build.sh
ARCH=x86_64 ./build.sh
```

The script produces an ad-hoc signed local bundle. It is not Developer ID signed or notarised. macOS security prompts and behaviour may differ between OS versions.

## Configuration

The options panel currently provides:

| Setting | Description |
|---|---|
| Latitude / longitude | Centre of the map and ADS-B search area. The initial default is around LECU / Madrid-Cuatro Vientos. |
| Zoom | Map scale. |
| Refresh interval | Minimum interval between traffic refreshes; provider limits may impose a longer interval. |
| Centre label | Short label shown at the map centre, for example `LECU`. |
| ADS-B API key | Optional `adsb.lol` key. When present, `adsb.lol` is tried before `adsb.fi`. |
| Map style | Free darkened OpenStreetMap tiles or optional CARTO Dark Matter. |
| CARTO API key | Used only when CARTO is selected. If CARTO fails, FlightSaver falls back to OpenStreetMap. |
| Display toggles | Aircraft labels, trails, distance rings, traffic / featured-aircraft panel and status line. |

Settings and optional provider keys are stored in the current user's macOS ScreenSaver preferences. They are not uploaded to the FlightSaver repository. The ADS-B key is sent to `adsb.lol` as an `X-API-Key` header; the CARTO key is sent to CARTO as part of its tile request URL.

## Data sources and network behaviour

### ADS-B traffic

FlightSaver currently supports ADSBExchange-v2-style responses from:

- `adsb.fi` — the default first provider when no `adsb.lol` key is configured.
- `adsb.lol` — used first when a key is configured; otherwise retained as a lower-frequency fallback.

The app pauses a provider temporarily after rate limits or access errors and can switch to the other provider. Availability, coverage, aircraft metadata and rate limits are controlled by the data providers and may change. Use each provider in accordance with its current terms and acceptable-use policy.

### Aircraft photographs — Planespotters.net

FlightSaver uses the public Planespotters photo endpoints without an API key:

1. Search by registration: `https://api.planespotters.net/pub/photos/reg/{registration}`.
2. If no usable photo is returned, try the ICAO 24-bit hex endpoint: `https://api.planespotters.net/pub/photos/hex/{hex}`.
3. Download the returned thumbnail from the photo CDN, show the photographer credit and link the image to its original Planespotters page.

Requests identify the application with this User-Agent, including the repository URL as the maintainer contact:

```http
User-Agent: FlightSaver/1.1.1 (+https://github.com/Isaaker/FlightSaver)
```

Only photo metadata is cached in memory for up to 24 hours. A negative lookup is cached too, to avoid repeating a search when a photo is unavailable. The thumbnail is fetched from the image CDN and is not written to FlightSaver's disk cache. Not every aircraft has a matching photograph.

Please respect Planespotters.net's current API rules, rate limits, attribution requirements and image rights. FlightSaver does not claim ownership of third-party photographs.

### Maps

- **OpenStreetMap** is the default no-key map source. Standard OSM tiles are transformed locally into a dark appearance. The visible map attribution must remain in place.
- **CARTO Dark Matter** is optional and requires your own CARTO key. A failed CARTO request falls back to OpenStreetMap.

Map tiles are cached locally under the user's macOS Caches directory for up to seven days. The cache is not part of the source repository and can be removed by the user at any time. Use map providers in accordance with their current tile usage policies and terms.

## Privacy

FlightSaver has no account system, analytics SDK or telemetry service. Network requests are needed for the app to work and disclose limited information to the relevant provider:

- ADS-B providers receive the configured map centre and requested search radius.
- Map tile providers receive the tile coordinates requested by the current view.
- Planespotters receives the selected aircraft's registration or ICAO hex to look up a photo.
- CARTO receives its API key when CARTO is selected.

See [PRIVACY.md](PRIVACY.md) for details. Do not share screenshots, diagnostic output or configuration exports that reveal API keys or a private map location.

## Troubleshooting

- **No aircraft appear:** check the centre coordinates, network connection and status line. ADS-B coverage depends on receivers and provider availability.
- **No aircraft photo:** the aircraft may not have a Planespotters image, or its registration / hex may be missing from the traffic feed. The card remains usable without a photo.
- **Planespotters returns HTTP 403:** verify that the installed build is current and that its User-Agent contains the repository contact URL shown above. The app will attempt the hex fallback after a registration lookup failure; rate limiting (HTTP 429) is handled separately.
- **CARTO says an API key is required:** either enter a valid key in Options or select the free OpenStreetMap style.
- **Map tiles do not appear:** check the network and try the free OpenStreetMap style. Some tile providers may throttle automated clients.
- **The old version is still visible:** reinstall with `./build.sh --install`, then reopen Screen Saver settings. On some macOS releases it can help to restart the screen saver process or log out and back in.
- **The screen saver behaves differently on a newer macOS release:** attach your macOS version, Mac architecture and a short reproduction to a bug report. Screen saver hosting APIs have changed across macOS versions.

## Development and contribution

See [CONTRIBUTING.md](CONTRIBUTING.md) for local checks, reporting guidelines and pull request expectations. The GitHub Actions workflow performs source-contract checks and a native macOS build. It deliberately does not call live ADS-B, map or photo APIs during CI.

## Project documents

- [CHANGELOG.md](CHANGELOG.md) — user-visible changes.
- [CONTRIBUTING.md](CONTRIBUTING.md) — contribution guide.
- [SECURITY.md](SECURITY.md) — vulnerability reporting policy.
- [PRIVACY.md](PRIVACY.md) — data and network privacy summary.
- [docs/PLANESPOTTERS.md](docs/PLANESPOTTERS.md) — photo lookup order, User-Agent and network diagnostics.
- [SUPPORT.md](SUPPORT.md) — where to ask questions.
- [AUTHORS.md](AUTHORS.md) and [NOTICE.md](NOTICE.md) — authorship and third-party notices.
- [LICENSE](LICENSE) — MIT License.

## Disclaimer and trademarks

FlightSaver is an independent community project and is not affiliated with, endorsed by or supported by Apple, OpenStreetMap, CARTO, Planespotters.net, adsb.fi or adsb.lol. All third-party names and marks belong to their respective owners. Data may be delayed, incomplete, unavailable or inaccurate.
