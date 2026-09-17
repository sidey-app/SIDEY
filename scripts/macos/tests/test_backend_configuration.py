import json
import plistlib
from pathlib import Path
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[3]


class BackendConfigurationTests(unittest.TestCase):
    def test_distribution_plists_share_sidey_api_and_public_google_configuration(self):
        for name in ["SIDEY-Info.plist", "SIDEYAppStore-Info.plist"]:
            with self.subTest(distribution=name):
                with (ROOT / "macos/Config" / name).open("rb") as source:
                    info = plistlib.load(source)
                self.assertEqual(info["SIDEYAPIBaseURL"], "$(SIDEY_API_BASE_URL)")
                self.assertEqual(info["SIDEYGoogleClientID"], "$(SIDEY_GOOGLE_CLIENT_ID)")
                self.assertNotIn("SIDEYSupabaseURL", info)
                self.assertNotIn("SIDEYAppStoreVerifierURL", info)

    def test_google_loopback_and_apple_login_capabilities_are_declared(self):
        for name in ["SIDEY.entitlements", "SIDEYAppStore.entitlements"]:
            with (ROOT / "macos/Config" / name).open("rb") as source:
                entitlements = plistlib.load(source)
            self.assertEqual(entitlements["com.apple.developer.applesignin"], ["Default"])
        self.assertTrue(entitlements["com.apple.security.app-sandbox"])
        self.assertTrue(entitlements["com.apple.security.network.client"])
        self.assertTrue(entitlements["com.apple.security.network.server"])

    def test_package_graph_retains_sparkle_without_supabase_runtime(self):
        project = ROOT / "macos/SIDEY.xcodeproj/project.pbxproj"
        result = subprocess.run(["plutil", "-convert", "json", "-o", "-", str(project)],
                                check=True, capture_output=True, text=True)
        objects = json.loads(result.stdout)["objects"]
        packages = [value for value in objects.values() if value["isa"] == "XCRemoteSwiftPackageReference"]
        self.assertEqual([value["repositoryURL"] for value in packages],
                         ["https://github.com/sparkle-project/Sparkle"])
        for value in objects.values():
            if value["isa"] == "XCSwiftPackageProductDependency":
                self.assertIn(value["package"], objects)
                self.assertEqual(value["productName"], "Sparkle")
        resolved = ROOT / "macos/SIDEY.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
        self.assertEqual([pin["identity"] for pin in json.loads(resolved.read_text())["pins"]], ["sparkle"])

    def test_optional_integration_fixture_declares_paths_without_embedded_tokens(self):
        with (ROOT / "macos/Config/SIDEYTests-Info.plist").open("rb") as source:
            info = plistlib.load(source)
        self.assertEqual(info["SIDEYIntegrationSessionOneFile"], "$(SIDEY_INTEGRATION_SESSION_ONE_FILE)")
        self.assertEqual(info["SIDEYIntegrationSessionTwoFile"], "$(SIDEY_INTEGRATION_SESSION_TWO_FILE)")
        self.assertNotIn("SIDEYSupabasePublishableKey", info)


if __name__ == "__main__":
    unittest.main()
