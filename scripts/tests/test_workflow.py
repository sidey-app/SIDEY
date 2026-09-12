import contextlib
import io
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('workflow', Path(__file__).parents[1] / 'workflow.py')
w = importlib.util.module_from_spec(spec)
spec.loader.exec_module(w)


class WorkflowTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.remote = self.root / 'origin.git'
        self.primary = self.root / 'main'
        self.other = self.root / 'other'
        self.command(self.root, 'git', 'init', '--bare', str(self.remote))
        self.command(self.root, 'git', 'clone', str(self.remote), str(self.primary))
        self.configure(self.primary)
        w.git(self.primary, 'checkout', '-b', 'main')
        (self.primary / 'README.md').write_text('initial\n')
        self.commit(self.primary, 'initial')
        w.git(self.primary, 'push', '-u', 'origin', 'main')
        w.git(self.remote, 'symbolic-ref', 'HEAD', 'refs/heads/main')
        self.command(self.root, 'git', 'clone', str(self.remote), str(self.other))
        self.configure(self.other)

    def command(self, root, *args):
        return w.run(root, *args)

    def configure(self, root):
        w.git(root, 'config', 'user.email', 'workflow@example.test')
        w.git(root, 'config', 'user.name', 'Workflow test')
        w.git(root, 'config', 'commit.gpgsign', 'false')

    def commit(self, root, message):
        w.git(root, 'add', '.')
        w.git(root, 'commit', '-m', message)

    def start(self, name='task', platform='shared'):
        path = self.root / name
        with contextlib.redirect_stdout(io.StringIO()):
            w.main(['--repo', str(self.primary), 'start', name, '--platform', platform, '--worktree', str(path)])
        return path

    def test_recovers_server_merge_after_lost_client_response_only_for_checked_head(self):
        path = self.start()
        (path / 'change.md').write_text('task')
        self.commit(path, 'task change')
        task = w.read_state(path)['task']
        task['checked'] = {'head': w.head(path), 'snapshot': w.snapshot(path)}
        w.git(self.primary, 'merge', '--no-ff', '-m', 'merge task', 'shared/task')
        remote = w.head(self.primary)
        pr = dict(number=42, headRefOid=w.head(path), mergeCommit={'oid': remote}, isCrossRepository=False)
        real_run = w.run
        def response(root, *args, **kwargs):
            return json.dumps([pr]) if args[0] == 'gh' else real_run(root, *args, **kwargs)
        with patch.object(w, 'run', side_effect=response):
            recovered = w.recover_merged_task(path, task, remote)
            self.assertEqual(recovered['pr'], '42')
            self.assertEqual(recovered['status'], 'integrated')
            (path / 'change.md').write_text('unchecked change')
            self.assertIsNone(w.recover_merged_task(path, task, remote))
            (path / 'change.md').write_text('task')
            pr['headRefOid'] = 'unrelated'
            self.assertIsNone(w.recover_merged_task(path, task, remote))

    def advance(self):
        (self.other / 'advance.md').write_text('remote update\n')
        self.commit(self.other, 'advance main')
        w.git(self.other, 'push', 'origin', 'main')
        return w.head(self.other)

    def test_start_fetches_real_remote_not_stale_tracking_ref(self):
        old = w.git(self.primary, 'rev-parse', 'origin/main')
        new = self.advance()
        self.assertNotEqual(old, new)
        task = self.start()
        self.assertEqual(w.head(task), new)

    def test_start_preserves_another_dirty_worktree(self):
        (self.primary / 'README.md').write_text('in progress\n')
        (self.primary / 'untracked.swift').write_text('user source\n')
        self.start()
        self.assertEqual((self.primary / 'README.md').read_text(), 'in progress\n')
        self.assertTrue((self.primary / 'untracked.swift').exists())

    def test_start_refuses_existing_directory_and_duplicate_owner(self):
        task = self.start()
        with self.assertRaises(w.WorkflowError):
            w.main(['--repo', str(self.primary), 'start', 'task', '--platform', 'shared', '--worktree', str(task)])

    def test_moved_file_checks_deleted_platform_path(self):
        (self.primary / 'macos').mkdir()
        (self.primary / 'macos/source.swift').write_text('native\n')
        self.commit(self.primary, 'fixture')
        w.git(self.primary, 'push')
        task = self.start()
        w.git(task, 'mv', 'macos/source.swift', 'source.swift')
        paths = w.changed_paths(task, 'origin/main', dirty=True)
        self.assertIn('macos/source.swift', paths)
        with self.assertRaises(w.WorkflowError):
            w.validate_paths('shared/task', paths)

    def test_untracked_platform_file_cannot_escape_guard(self):
        task = self.start()
        (task / 'windows').mkdir()
        (task / 'windows/new.cs').write_text('source\n')
        with self.assertRaises(w.WorkflowError):
            w.validate_paths('shared/task', w.changed_paths(task, 'origin/main', dirty=True))

    def test_main_cannot_implement(self):
        with self.assertRaises(w.WorkflowError):
            w.validate_paths('main', ['README.md'])

    def test_platform_branches_reject_shared_changes(self):
        for name in ('macos/task', 'windows/task'):
            with self.assertRaises(w.WorkflowError):
                w.validate_paths(name, ['docs/DECISIONS.md'])

    def test_shared_commits_already_in_main_are_excluded(self):
        task = self.start(platform='macos')
        (task / 'macos').mkdir()
        (task / 'macos/source.swift').write_text('native\n')
        self.commit(task, 'native')
        new = self.advance()
        w.fetch_main(task)
        w.git(task, 'merge', '--no-edit', new)
        self.assertEqual(w.changed_paths(task, new), ['macos/source.swift'])

    def test_check_invalidates_when_main_advances_during_checks(self):
        task = self.start()
        with patch.object(w, 'local_checks', side_effect=lambda *_: self.advance()):
            with self.assertRaisesRegex(w.WorkflowError, 'changed during'):
                w.check_task(task, 'task')
        self.assertNotIn('checked', w.owned_task(task, 'task'))

    def test_check_invalidates_when_source_changes_during_checks(self):
        task = self.start()
        with patch.object(w, 'local_checks', side_effect=lambda *_: (task / 'new.txt').write_text('new')):
            with self.assertRaisesRegex(w.WorkflowError, 'changed during'):
                w.check_task(task, 'task')

    def test_attestation_rejects_edit_after_check_and_staging(self):
        task = self.start()
        (task / 'README.md').write_text('task changes')
        with patch.object(w, 'local_checks'):
            state = w.check_task(task, 'task')
        w.attest(task, state, state['base'])
        w.git(task, 'add', 'README.md')
        with self.assertRaises(w.WorkflowError):
            w.attest(task, state, state['base'])

    def test_sync_refuses_dirty_task_and_other_owner(self):
        task = self.start()
        (task / 'README.md').write_text('unfinished')
        with self.assertRaises(w.WorkflowError):
            w.main(['--repo', str(task), 'sync', 'task'])
        with self.assertRaises(w.WorkflowError):
            w.owned_task(self.primary, 'task')

    def test_offline_fetch_does_not_reuse_previous_check(self):
        task = self.start()
        w.git(task, 'remote', 'set-url', 'origin', str(self.root / 'missing.git'))
        with self.assertRaises(w.WorkflowError):
            w.check_task(task, 'task')

    def test_primary_main_update_refuses_dirty_state(self):
        remote = self.advance()
        w.fetch_main(self.primary)
        old = w.head(self.primary)
        (self.primary / 'README.md').write_text('owned by user')
        with self.assertRaisesRegex(w.WorkflowError, 'completion pending'):
            w.update_main(self.primary, remote)
        self.assertEqual(w.head(self.primary), old)
        self.assertEqual((self.primary / 'README.md').read_text(), 'owned by user')

    def test_scopes_include_catalog_database_and_verifier(self):
        self.assertEqual(set(w.required_scopes(['assets/v1/commerce-catalog.json'])),
                         {'shared', 'macos', 'windows', 'web', 'server', 'database'})
        self.assertIn('windows', w.required_scopes(['website/src/pages/ko/terms.md']))


if __name__ == '__main__':
    unittest.main()
