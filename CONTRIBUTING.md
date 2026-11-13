# Contributing to FlightSaver

Thanks for considering a contribution. FlightSaver is a small native macOS project; the goal is a dependable, transparent aircraft-traffic screen saver, not an aviation operational tool.

## Before opening an issue

- Search existing issues to avoid duplicates.
- Include the FlightSaver version, macOS version, Mac architecture (`arm64` or `x86_64`) and a concise reproduction.
- For photo problems, include the HTTP status, the endpoint type (registration or hex) and whether the image CDN request succeeds. Do not include private API keys.
- For map problems, include the selected map provider and whether OpenStreetMap fallback works.
- Redact exact coordinates, local paths, personal identifiers and API keys from screenshots or logs unless you explicitly intend to share them.
- Never attach proprietary aircraft files, copyrighted photographs, private datasets or credentials that you do not have permission to redistribute.

## Development setup

Requirements:

- macOS 12 or newer.
- Xcode Command Line Tools (`swiftc`, `codesign` and macOS SDK).
- Python 3.10+ for repository contract tests.

Build locally:

```bash
./build.sh
```

Install the compiled screen saver for the current user:

```bash
./build.sh --install
```

Run the offline source-contract tests:

```bash
python3 -m unittest discover -s tests -v
```

The CI workflow builds on macOS and runs offline checks. It intentionally does not make live requests to ADS-B, OpenStreetMap, CARTO or Planespotters services.

## Code and network changes

- Keep provider identity and User-Agent strings centralised in `Sources/NetworkIdentity.swift`.
- Keep Planespotters registration lookup as the primary photo search and ICAO hex as the fallback.
- Do not bypass rate limits, access controls or provider error responses. Handle 429 responses with backoff and respect current provider policies.
- Preserve photographer credit and the original photo-page link. Do not bundle or redistribute third-party photographs without permission.
- Keep map-provider attribution visible and preserve a usable no-key OpenStreetMap option.
- Do not add analytics, telemetry or unrelated network calls without clearly documenting the privacy impact.
- Do not log API keys, full private coordinates or personal data.
- Avoid introducing third-party dependencies when the macOS SDK or Swift standard library is sufficient.

## Pull requests

1. Keep each pull request focused and explain the user-visible behaviour.
2. Add or update offline tests for parsing, request construction, fallback logic or build tooling where feasible.
3. Update `CHANGELOG.md` for user-visible changes.
4. Update README / privacy documentation when settings, permissions, data flows or provider behaviour change.
5. Include test evidence (macOS version, architecture and build result). Network-dependent behaviour should include redacted status-code diagnostics, not secrets.
6. Do not commit generated `build/` output, caches, local preferences, screenshots containing private data or API keys.

## Versioning and releases

`VERSION` is the canonical release version. The build script copies it into the screen saver bundle metadata. Stable releases use tags in the form `vMAJOR.MINOR.PATCH`; the release workflow verifies the tag against `VERSION`, builds on macOS and attaches a ZIP containing the `.saver` bundle.

## Licence

By submitting a contribution, you agree that it may be distributed under the repository's MIT License. You retain ownership of your contribution.
