import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import build_provenance as p
from open_current import verify_running


class ProvenanceTests(unittest.TestCase):
    def test_untracked_source_counts_but_personal_state_and_cache_do_not(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            subprocess.run(['git', 'init', str(root)], check=True, capture_output=True)
            subprocess.run(['git', '-C', str(root), '-c', 'user.name=T', '-c', 'user.email=t@example.test',
                            '-c', 'commit.gpgsign=false', 'commit', '--allow-empty', '-m', 'fixture'], check=True, capture_output=True)
            source = root / 'macos/SIDEY/New.swift'
            source.parent.mkdir(parents=True)
            before = p.source_state(root)['input_hash']
            source.write_text('struct New {}')
            after = p.source_state(root)['input_hash']
            self.assertNotEqual(before, after)
            for path in ['macos/SIDEY/.env', 'macos/SIDEY/.DS_Store', 'macos/SIDEY.xcodeproj/xcuserdata/state',
                         'build/review/output.swift', '_workspace/other/macos/SIDEY/New.swift']:
                file = root / path
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_text('not a build input')
            self.assertEqual(after, p.source_state(root)['input_hash'])

    def test_running_proof_rejects_same_version_other_build_scheme_and_old_process(self):
        ticket = dict(session='new-session', build_id='new-build', commit='new-commit', input_hash='new-input',
                      target='SIDEYAppStore', configuration='Debug')
        receipt = {**ticket, 'executable': '/new/App', 'window_ready': True}
        verify_running(ticket, receipt, '/new/App', '/new/App')
        for key in ticket:
            with self.subTest(key=key), self.assertRaises(RuntimeError):
                verify_running(ticket, {**receipt, key: 'old'}, '/new/App', '/new/App')
        with self.assertRaises(RuntimeError):
            verify_running(ticket, receipt, '/new/App', '/Applications/old/App')
        with self.assertRaises(RuntimeError):
            verify_running(ticket, {**receipt, 'window_ready': False}, '/new/App', '/new/App')


if __name__ == '__main__':
    unittest.main()
