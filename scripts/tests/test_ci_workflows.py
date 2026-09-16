from pathlib import Path
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[2]
WORKFLOWS = ROOT / '.github' / 'workflows'


class CiWorkflowTests(unittest.TestCase):
    def read(self, name):
        return (WORKFLOWS / name).read_text(encoding='utf-8')

    def test_integration_is_the_automatic_shared_validation_entrypoint(self):
        integration = self.read('integration.yml')
        self.assertIn(
            'python3 scripts/skills/validate_contributor_architecture.py',
            integration,
        )
        self.assertIn(
            'python3 -m unittest discover -s scripts/skills/release-notes/tests',
            integration,
        )
        self.assertNotIn('--require-windows-instruction-foundation', integration)
        self.assertIn("python -X utf8 ./windows/tools/sync_product_assets.py --check", integration)
        self.assertIn('Run Windows app smoke', integration)
        for name in ('release-metadata.yml',):
            with self.subTest(workflow=name):
                workflow = self.read(name)
                self.assertIn('  workflow_dispatch:', workflow)
                self.assertNotIn('  pull_request:', workflow)
                self.assertNotIn('  push:', workflow)

    def test_integration_revalidates_edited_pull_request_bodies(self):
        workflow = self.read('integration.yml')
        self.assertIn(
            'types: [opened, synchronize, reopened, edited]',
            workflow,
        )

    def test_pages_reuses_the_tested_build_for_deployment(self):
        workflow = self.read('pages.yml')
        self.assertNotIn('  pull_request:', workflow)
        self.assertEqual(workflow.count('pnpm install --frozen-lockfile'), 1)
        self.assertEqual(workflow.count('pnpm test'), 1)
        self.assertIn('name: Upload tested website build', workflow)
        self.assertIn('name: Download tested website build', workflow)

    def test_public_checkout_excludes_backend_implementation_and_operations(self):
        private_paths = (
            'supabase', 'services/app-store-verifier', 'scripts/supabase',
            'scripts/download-metrics', 'scripts/configure_supabase_staging.sh',
            '.github/workflows/database.yml', '.github/workflows/download-metrics.yml',
        )
        # Ignore leftover local build caches after the split, but reject new
        # untracked source too. Deleted files may still appear in the index.
        candidates = subprocess.check_output([
            'git', '-C', str(ROOT), 'ls-files', '-z', '--cached', '--others',
            '--exclude-standard',
        ]).decode().split('\0')
        unexpected = [path for path in candidates
                      if path and (ROOT / path).exists()
                      and any(path == owned or path.startswith(owned + '/')
                              for owned in private_paths)]
        self.assertEqual(unexpected, [],
                         'Backend implementation belongs in sidey-app/sidey-backend')
        integration = self.read('integration.yml')
        self.assertNotIn('  database:', integration)
        self.assertNotIn('  server:', integration)
        self.assertIn('needs: [scope, shared, macos, windows, web]', integration)


if __name__ == '__main__':
    unittest.main()
