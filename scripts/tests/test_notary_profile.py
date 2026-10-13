import hashlib
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class NotaryProfileTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="pinboardshot-notary-test-", dir="/private/tmp")
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        fake = self.directory / "xcrun"
        fake.write_text(
            '#!/bin/sh\n'
            'printf "%s\\n" "$@" > "$NOTARY_TEST_ARGUMENTS"\n'
            'if [ "$NOTARY_TEST_STATUS" = 0 ]; then printf "%s\\n" "$NOTARY_TEST_BODY"; exit 0; fi\n'
            'printf "No Keychain password item found: PRIVATE_ERROR_SENTINEL\\n" >&2\n'
            'exit 69\n'
        )
        fake.chmod(0o755)
        self.environment = dict(
            os.environ,
            PATH=str(self.directory) + os.pathsep + os.environ["PATH"],
            NOTARY_TEST_ARGUMENTS=str(self.directory / "arguments"),
            NOTARY_TEST_STATUS="69",
            NOTARY_TEST_BODY='{"history":[]}',
        )

    def run_script(self, script, *arguments):
        return subprocess.run(
            [str(ROOT / "scripts" / script), *arguments],
            cwd=ROOT, env=self.environment, text=True, capture_output=True, timeout=10,
        )

    def test_success_uses_the_explicit_profile_without_exposing_history(self):
        self.environment["NOTARY_TEST_STATUS"] = "0"
        result = self.run_script("check-notary-profile.sh", "Configured-profile")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            (self.directory / "arguments").read_text().splitlines(),
            ["notarytool", "history", "--keychain-profile", "Configured-profile", "--output-format", "json"],
        )
        self.assertNotIn("history", result.stdout)

    def test_failure_reports_access_not_absence_and_hides_vendor_error(self):
        result = self.run_script("check-notary-profile.sh")
        self.assertEqual(result.returncode, 78)
        self.assertIn("execution context", result.stderr)
        self.assertIn("before diagnosing", result.stderr)
        self.assertNotIn("PRIVATE_ERROR_SENTINEL", result.stdout + result.stderr)
        self.assertNotIn("No Keychain password item found", result.stderr)

    def test_success_exit_without_confirmed_history_is_not_accepted(self):
        self.environment["NOTARY_TEST_STATUS"] = "0"
        for body in ['{"status":"unknown"}', 'PRIVATE_ERROR_SENTINEL']:
            with self.subTest(body=body):
                self.environment["NOTARY_TEST_BODY"] = body
                result = self.run_script("check-notary-profile.sh")
                self.assertEqual(result.returncode, 78)
                self.assertIn("confirmed history", result.stderr)
                self.assertNotIn("PRIVATE_ERROR_SENTINEL", result.stdout + result.stderr)

    def test_both_release_entries_stop_before_changing_build_or_assets(self):
        info = plistlib.loads((ROOT / "Resources/Info.plist").read_bytes())
        observed = [
            ROOT / ".build/app/PinboardShot.app/Contents/MacOS/PinboardShot",
            ROOT / ".build/app/PinboardShot.app/Contents/_CodeSignature/CodeResources",
            ROOT / ".build/update-feed/appcast.xml",
        ]

        def fingerprints():
            return {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in observed if p.exists()}

        before = fingerprints()
        for script in ["prepare-update.sh", "release-artifacts.sh"]:
            with self.subTest(script=script):
                result = self.run_script(script, info["CFBundleShortVersionString"], info["CFBundleVersion"])
                self.assertEqual(result.returncode, 78, result.stdout + result.stderr)
                self.assertIn("execution context", result.stderr)
                self.assertEqual(before, fingerprints())


if __name__ == "__main__":
    unittest.main()
