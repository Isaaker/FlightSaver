# Contributing to FlightSaver

Thanks for your interest in FlightSaver. The project welcomes bug reports, reproducible diagnostics, accessibility feedback and feature suggestions. The goal is a dependable, transparent aircraft-traffic screen saver, not an aviation operational tool.

## Please read the licence first

Unless a file says otherwise, FlightSaver's first-party source code and documentation are distributed under **CC BY-NC-ND 4.0**. This licence permits non-commercial sharing of unmodified material, and permits non-commercial creation/reproduction of adaptations, but it does not permit sharing adapted material.

For that reason, **do not submit an unsolicited pull request containing modified project code or documentation**. A public pull request may make adapted material available to others. Contact the maintainers first and obtain written approval plus a separate agreement covering the proposed contribution and its distribution. See [`LICENSING.md`](LICENSING.md).

You may still report bugs, ask questions and suggest changes through GitHub Issues. An issue or suggestion does not automatically grant the project rights to use or distribute third-party material you attach.

## Before opening an issue

- Search existing issues to avoid duplicates.
- Include the FlightSaver version, macOS version, Mac architecture (`arm64` or `x86_64`) and a concise reproduction.
- For photo problems, include the HTTP status, the endpoint type (registration or hex) and whether the image CDN request succeeds. Do not include private API keys.
- For map problems, include the selected map provider and whether OpenStreetMap fallback works.
- Redact exact coordinates, local paths, personal identifiers and API keys from screenshots or logs unless you explicitly intend to share them.
- Never attach proprietary aircraft files, copyrighted photographs, private datasets or credentials that you do not have permission to share.

## Development setup

Requirements for local validation:

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

## Code and network design notes

For maintainers and contributors with prior written approval:

- Keep provider identity and User-Agent strings centralised in `Sources/NetworkIdentity.swift`.
- Keep Planespotters registration lookup as the primary photo search and ICAO hex as the fallback.
- Do not bypass rate limits, access controls or provider error responses. Handle 429 responses with backoff and respect current provider policies.
- Preserve photographer credit and the original photo-page link. Do not bundle or redistribute third-party photographs without permission.
- Keep map-provider attribution visible and preserve a usable no-key OpenStreetMap option.
- Do not add analytics, telemetry or unrelated network calls without clearly documenting the privacy impact.
- Do not log API keys, full private coordinates or personal data.
- Avoid introducing third-party dependencies when the macOS SDK or Swift standard library is sufficient.

## Versioning and releases

`VERSION` is the canonical application version. The build script copies it into the screen saver bundle metadata. Stable releases use tags in the form `vMAJOR.MINOR.PATCH`; the release workflow verifies the tag against `VERSION`, builds on macOS and attaches a ZIP containing the `.saver` bundle.

## Licence questions

The project is not offered under an OSI-approved open-source software licence. For a commercial licence, permission to distribute adapted material, or permission to contribute code, contact Ramshackle Code Organization at [ramshackle-code@piscinadeentropia.es](mailto:ramshackle-code@piscinadeentropia.es). See [`LICENSING.md`](LICENSING.md).
