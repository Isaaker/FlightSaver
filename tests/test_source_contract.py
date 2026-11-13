from pathlib import Path
import plistlib
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]


class RepositoryContractTests(unittest.TestCase):
    def test_planespotters_user_agent_has_contact_url(self):
        source = (ROOT / "Sources" / "NetworkIdentity.swift").read_text(encoding="utf-8")
        self.assertIn("FlightSaver/1.1.1 (+https://github.com/Isaaker/FlightSaver)", source)
        self.assertRegex(source, r"https://github\.com/Isaaker/FlightSaver")

    def test_photo_lookup_uses_registration_then_hex(self):
        source = (ROOT / "Sources" / "AircraftPhotoService.swift").read_text(encoding="utf-8")
        registration_path = 'https://api.planespotters.net/pub/photos/reg/'
        hex_path = 'https://api.planespotters.net/pub/photos/hex/'
        self.assertIn(registration_path, source)
        self.assertIn(hex_path, source)
        self.assertLess(source.index(registration_path), source.index(hex_path))
        self.assertIn("if fallbackToHex", source)
        self.assertIn("// Incluye HTTP 403 y errores de transporte: el hex es el último recurso.", source)
        self.assertIn("self.resolveHex(self.featuredHex ?? \"\", lookupID: activeLookupID)", source)

    def test_photo_requests_send_the_shared_user_agent(self):
        source = (ROOT / "Sources" / "AircraftPhotoService.swift").read_text(encoding="utf-8")
        self.assertGreaterEqual(source.count('request.setValue(NetworkIdentity.userAgent, forHTTPHeaderField: "User-Agent")'), 2)
        self.assertIn('request.setValue("image/*", forHTTPHeaderField: "Accept")', source)

    def test_photo_parser_skips_incomplete_records(self):
        source = (ROOT / "Sources" / "AircraftPhotoService.swift").read_text(encoding="utf-8")
        self.assertIn("for photo in photos", source)
        self.assertIn("else { continue }", source)

    def test_shared_user_agent_is_used_by_all_network_clients(self):
        for filename in ("AircraftPhotoService.swift", "FlightFeed.swift", "TileStore.swift"):
            source = (ROOT / "Sources" / filename).read_text(encoding="utf-8")
            self.assertIn("NetworkIdentity.userAgent", source, filename)

    def test_bundle_and_preferences_identifiers_match(self):
        plist = plistlib.loads((ROOT / "Info.plist").read_bytes())
        settings = (ROOT / "Sources" / "Settings.swift").read_text(encoding="utf-8")
        identifier = "com.isaaker.flightsaver"
        self.assertEqual(plist["CFBundleIdentifier"], identifier)
        self.assertIn(f'module = "{identifier}"', settings)
        self.assertIn('com.local.FlightSaver', settings)
        self.assertIn('migrateLegacyPreferencesIfNeeded()', settings)

    def test_build_script_uses_canonical_version_file(self):
        version = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
        build = (ROOT / "build.sh").read_text(encoding="utf-8")
        self.assertRegex(version, r"^\d+\.\d+\.\d+$")
        self.assertIn(' < VERSION', build)
        self.assertIn('CFBundleShortVersionString', build)

    def test_documentation_and_repository_policies_exist(self):
        required = [
            "README.md", "README.es.md", "LICENSE", "SECURITY.md", "CONTRIBUTING.md",
            "CHANGELOG.md", "AUTHORS.md", "NOTICE.md", "PRIVACY.md", "SUPPORT.md",
            "CODE_OF_CONDUCT.md", ".github/workflows/ci.yml", ".github/workflows/release.yml",
        ]
        for relative in required:
            with self.subTest(path=relative):
                self.assertTrue((ROOT / relative).is_file())


if __name__ == "__main__":
    unittest.main()
