from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
WORKFLOWS = ROOT / '.github' / 'workflows'


class CiWorkflowTests(unittest.TestCase):
    def read(self, name):
        return (WORKFLOWS / name).read_text(encoding='utf-8')

    def test_integration_is_the_automatic_database_entrypoint(self):
        integration = self.read('integration.yml')
        self.assertIn("python -X utf8 ./windows/tools/sync_product_assets.py --check", integration)
        self.assertIn('Run Windows app smoke', integration)
        workflow = self.read('database.yml')
        self.assertIn('  workflow_dispatch:', workflow)
        self.assertNotIn('  pull_request:', workflow)
        self.assertNotIn('  push:', workflow)

    def test_pages_reuses_the_tested_build_for_deployment(self):
        workflow = self.read('pages.yml')
        self.assertNotIn('  pull_request:', workflow)
        self.assertEqual(workflow.count('pnpm install --frozen-lockfile'), 1)
        self.assertEqual(workflow.count('pnpm test'), 1)
        self.assertIn('name: Upload tested website build', workflow)
        self.assertIn('name: Download tested website build', workflow)

    def test_download_metrics_uses_one_runner(self):
        workflow = self.read('download-metrics.yml')
        self.assertEqual(workflow.count('runs-on: ubuntu-latest'), 1)
        self.assertEqual(workflow.count('actions/checkout@v7'), 1)
        self.assertEqual(workflow.count('actions/setup-node@v6'), 1)


if __name__ == '__main__':
    unittest.main()
