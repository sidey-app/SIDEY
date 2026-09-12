from pathlib import Path
import sys
import unittest
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).parents[1]))
import verify_release_consistency as v


class ReleaseDisplayTests(unittest.TestCase):
    def test_missing_duplicate_and_reversed_markers_fail(self):
        for content in ('no region', '<!-- sidey-release:macos:start -->' * 2,
                        '<!-- sidey-release:macos:end --><!-- sidey-release:macos:start -->'):
            with patch.object(v, 'read', return_value=content), self.assertRaises(v.ConsistencyError):
                v.release_display('macos')

    def test_history_and_copy_outside_display_are_not_version_mirrors(self):
        content = 'Historical v0.1.0\n<!-- sidey-release:macos:start -->\n현재 `v1.2.1`(build 29)\n<!-- sidey-release:macos:end -->\nFuture plans'
        with patch.object(v, 'read', return_value=content):
            self.assertEqual(v.release_display('macos').strip(), '현재 `v1.2.1`(build 29)')
