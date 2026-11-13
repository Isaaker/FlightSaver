# Privacy

FlightSaver is designed to run locally as a macOS screen saver. It does not include an account system, advertising SDK, analytics SDK or telemetry endpoint.

## Information sent to providers

To display live information, FlightSaver makes requests to external providers:

| Provider | Information sent | Purpose |
|---|---|---|
| `adsb.fi` | Configured latitude, longitude and search radius | Retrieve nearby aircraft positions and metadata. |
| `adsb.lol` | Configured latitude, longitude and search radius; optional API key in the `X-API-Key` header | Retrieve nearby aircraft positions and metadata. |
| OpenStreetMap tile server | Requested map tile coordinates | Display the map. |
| CARTO, when selected | Requested map tile coordinates and the user-supplied CARTO key in the request URL | Display optional CARTO Dark Matter tiles. |
| Planespotters.net | Featured aircraft registration, or ICAO 24-bit hex when registration lookup fails | Find a matching aircraft photograph. |
| Planespotters image CDN | Thumbnail URL returned by the Planespotters API | Download the selected thumbnail. |

Requests identify the app with `FlightSaver/1.1.1 (+https://github.com/Isaaker/FlightSaver)`. Provider servers may process request metadata such as IP address, timestamp and user-agent under their own privacy policies.

## Local storage

- Screen saver options (including provider keys) are stored in the current user's macOS ScreenSaver preferences.
- Map tile data is stored in the user's macOS Caches directory and is considered valid for seven days. Expired files are ignored by the app but may remain on disk until the cache is cleared or macOS removes them.
- Planespotters lookup metadata, including negative lookup results, is cached in memory for up to 24 hours. Aircraft thumbnails are not stored in FlightSaver's disk cache.
- The app does not intentionally upload local preferences, screenshots or simulator files.

The settings store is macOS user preferences, not a dedicated secrets vault. Treat API keys as sensitive and do not share preference files or diagnostic captures that include them.

## Your choices

You can stop using the screen saver, clear provider keys in its Options panel, choose the no-key OpenStreetMap map, or clear FlightSaver's map cache from the macOS Caches directory. Network access is required for live aircraft, map tiles and optional aircraft photographs.

## Changes

This policy may be updated when providers, features or data flows change. The current version is maintained in this repository.
