import contextlib
import io
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parents[1]))
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

    def test_subprocess_output_decodes_utf8_and_legacy_locale(self):
        self.assertEqual(w.decode_output('기여자'.encode('utf-8')), '기여자')
        with patch.object(w.locale, 'getencoding', return_value='cp949'):
            self.assertEqual(w.decode_output('검증'.encode('cp949')), '검증')

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

    def test_recovers_server_squash_after_lost_client_response_only_for_checked_tree(self):
        path = self.start()
        (path / 'change.md').write_text('task')
        self.commit(path, 'task change')
        task = w.read_state(path)['task']
        task['checked'] = {'head': w.head(path), 'snapshot': w.snapshot(path), 'base': task['base']}
        task['merge_intent'] = {
            'head': w.head(path), 'base': task['base'], 'subject': 'squash task',
            'body_sha256': w.hashlib.sha256(b'').hexdigest(), 'coauthors': [],
        }
        w.git(self.primary, 'merge', '--squash', 'shared/task')
        self.commit(self.primary, 'squash task')
        remote = w.head(self.primary)
        pr = dict(number=42, headRefOid=w.head(path), mergeCommit={'oid': remote},
                  isCrossRepository=False, body='')
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

    def test_recovery_rejects_a_merge_with_different_content(self):
        path = self.start()
        (path / 'change.md').write_text('task')
        self.commit(path, 'task change')
        task = w.read_state(path)['task']
        task['checked'] = {'head': w.head(path), 'snapshot': w.snapshot(path), 'base': task['base']}
        task['merge_intent'] = {
            'head': w.head(path), 'base': task['base'], 'subject': 'expected subject',
            'body_sha256': w.hashlib.sha256(b'').hexdigest(), 'coauthors': [],
        }
        (self.primary / 'other.md').write_text('other')
        self.commit(self.primary, 'unrelated merge result')
        remote = w.head(self.primary)
        pr = dict(number=42, headRefOid=w.head(path), mergeCommit={'oid': remote},
                  isCrossRepository=False, body='')
        real_run = w.run
        def response(root, *args, **kwargs):
            return json.dumps([pr]) if args[0] == 'gh' else real_run(root, *args, **kwargs)
        with patch.object(w, 'run', side_effect=response):
            self.assertIsNone(w.recover_merged_task(path, task, remote))

    def squashed_macos_task(self):
        opener = self.primary / 'scripts/macos/open_current.sh'
        opener.parent.mkdir(parents=True)
        opener.write_text('#!/bin/sh\nexit 0\n')
        self.commit(self.primary, 'opener fixture')
        w.git(self.primary, 'push', 'origin', 'main')
        path = self.start(platform='macos')
        (path / 'macos').mkdir()
        (path / 'macos/source.swift').write_text('reviewed native change\n')
        self.commit(path, 'native task change')
        task = w.read_state(path)['task']
        task['checked'] = {'head': w.head(path), 'snapshot': w.snapshot(path), 'base': task['base']}
        w.git(self.primary, 'merge', '--squash', 'macos/task')
        self.commit(self.primary, 'squashed native change')
        task.update(status='main-updated', merge=w.head(self.primary))
        w.git(self.primary, 'push', 'origin', 'main')
        w.update_task(path, 'task', task)
        self.assertFalse(w.is_ancestor(path, task['checked']['head'], task['merge']))
        self.assertTrue(w.same_tree(path, task['checked']['head'], task['merge']))
        return path, task

    def test_open_accepts_squashed_checked_tree_after_main_advances(self):
        path, task = self.squashed_macos_task()
        (self.primary / 'later.md').write_text('subsequent reviewed change\n')
        self.commit(self.primary, 'advance after squash')
        w.git(self.primary, 'push', 'origin', 'main')
        remote = w.head(self.primary)
        self.assertFalse(w.same_tree(path, task['merge'], remote))
        real_run = w.run
        opened = []
        def response(root, *args, **kwargs):
            if Path(args[0]) == self.primary.resolve() / 'scripts/macos/open_current.sh':
                opened.append((root, args))
                return ''
            return real_run(root, *args, **kwargs)
        with patch.object(w, 'run', side_effect=response), contextlib.redirect_stdout(io.StringIO()):
            w.main(['--repo', str(path), 'open', '--task', 'task'])
        primary = self.primary.resolve()
        self.assertEqual(opened, [(primary, (str(primary / 'scripts/macos/open_current.sh'),
            '--worktree', str(primary), '--scheme', 'SIDEYAppStore'))])
        completed = w.read_state(path)['task']
        self.assertEqual(completed['status'], 'complete')
        self.assertEqual(completed['app_review']['main'], remote)
        self.assertEqual(completed['app_review']['source'], str(primary))

    def test_open_rejects_unverified_squash_and_wrong_app_without_launching(self):
        path, task = self.squashed_macos_task()
        invalid = [
            ('not integrated', {**task, 'status': 'started'}),
            ('wrong platform', {**task, 'platform': 'windows'}),
            ('wrong app', {**task, 'app': 'SIDEY'}),
            ('missing merge', {key: value for key, value in task.items() if key != 'merge'}),
            ('missing check', {key: value for key, value in task.items() if key != 'checked'}),
            ('missing checked head', {**task, 'checked': {}}),
            ('merge outside main', {**task, 'merge': task['checked']['head']}),
            ('different tree', {**task, 'merge': task['base']}),
            ('missing task', None),
        ]
        real_run = w.run
        def response(root, *args, **kwargs):
            if Path(args[0]) == self.primary.resolve() / 'scripts/macos/open_current.sh':
                self.fail('Unverified task must not launch the app')
            return real_run(root, *args, **kwargs)
        for reason, state in invalid:
            with self.subTest(reason=reason):
                w.update_task(path, 'task', state)
                with patch.object(w, 'run', side_effect=response), self.assertRaisesRegex(
                        w.WorkflowError, 'integrated and awaiting'):
                    w.main(['--repo', str(path), 'open', '--task', 'task'])
                self.assertEqual(w.read_state(path)['task'], state)

    def test_coauthors_come_from_real_trailer_blocks_and_deduplicate_email(self):
        messages = [
            'Example\nCo-authored-by: Not A Trailer <fake@example.test>\nMore text',
            'Change\n\nCo-authored-by: Codex <codex@openai.com>',
            'Another\n\nco-authored-by: codex <CODEX@OPENAI.COM>',
            'Third\n\nCo-authored-by: Person <person@example.test>',
        ]
        self.assertEqual(w.coauthor_trailers(self.primary, messages), [
            'Co-authored-by: Codex <codex@openai.com>',
            'Co-authored-by: Person <person@example.test>',
        ])

    def test_squash_body_normalizes_existing_trailers_and_preserves_others(self):
        body = ('Summary\n\nReviewed-by: Reviewer <reviewer@example.test>\n'
                'Co-authored-by: Codex <codex@openai.com>\n'
                'co-authored-by: codex <CODEX@OPENAI.COM>')
        result = w.squash_body(self.primary, body, [
            'Change\n\nCo-authored-by: Person <person@example.test>',
        ])
        self.assertEqual(result, ('Summary\n\nReviewed-by: Reviewer <reviewer@example.test>\n'
                                  'Co-authored-by: Codex <codex@openai.com>\n'
                                  'Co-authored-by: Person <person@example.test>'))

    def test_single_line_pr_body_is_parsed_as_a_commit_body_trailer(self):
        body = 'Co-authored-by: Person <person@example.test>'
        self.assertEqual(w.squash_body(self.primary, body, []), body)
        self.assertEqual(w.coauthor_trailers(self.primary, [w.pr_body_message(body)]), [body])

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

    def test_task_state_round_trips_korean_as_utf8(self):
        task = self.start()
        state = w.read_state(task)['task']
        state['merge_intent'] = {'subject': '한글 squash 제목'}
        w.update_task(task, 'task', state)
        state_path = w.common_dir(task) / 'sidey-workflow' / 'tasks.json'
        self.assertIn('한글 squash 제목', state_path.read_bytes().decode('utf-8'))
        self.assertEqual(w.read_state(task)['task']['merge_intent']['subject'], '한글 squash 제목')

    def test_legacy_locale_task_state_is_migrated_to_utf8(self):
        task = self.start()
        state_path = w.common_dir(task) / 'sidey-workflow' / 'tasks.json'
        state = w.read_state(task)
        state['task']['merge_intent'] = {'subject': '예전 한글 제목'}
        state_path.write_bytes(json.dumps(state, ensure_ascii=False).encode('cp949'))
        with patch.object(w.locale, 'getencoding', return_value='cp949'):
            self.assertEqual(w.read_state(task)['task']['merge_intent']['subject'], '예전 한글 제목')
        self.assertIn('예전 한글 제목', state_path.read_bytes().decode('utf-8'))

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

    def test_catalog_runs_public_consumers(self):
        self.assertEqual(set(w.required_scopes(['assets/v1/commerce-catalog.json'])),
                         {'shared', 'macos', 'windows', 'web'})
        self.assertIn('windows', w.required_scopes(['website/src/pages/ko/terms.md']))

    def test_contributor_architecture_only_changes_are_shared_only(self):
        paths = [
            'AGENTS.md',
            'windows/AGENTS.md',
            'windows/docs/AGENTS.md',
            'website/AGENTS.md',
            '.agents/skills/version-audit/SKILL.md',
            '.agents/skills/windows-tests/agents/openai.yaml',
            'scripts/validate_contributor_architecture.py',
            'scripts/tests/test_contributor_architecture.py',
            'scripts/validate_commit_message.py',
            'scripts/tests/test_validate_commit_message.py',
            '.githooks/prepare-commit-msg',
        ]
        self.assertEqual(w.required_scopes(paths), ['shared'])
        self.assertEqual(w.platform_for('windows/AGENTS.md'), 'shared')
        self.assertEqual(w.platform_for('website/AGENTS.md'), 'shared')
        self.assertEqual(w.validate_paths('shared/contributor-architecture', paths), 'shared')

    def test_contributor_classification_does_not_hide_product_changes(self):
        self.assertEqual(
            w.required_scopes(['AGENTS.md', 'macos/Sources/SIDEY/App.swift']),
            ['macos', 'shared'],
        )
        self.assertEqual(
            w.required_scopes(['website/AGENTS.md', 'website/src/pages/index.astro']),
            ['shared', 'web'],
        )

    def test_commit_text_validation_fails_before_repository_mutation(self):
        w.require_valid_commit_text('Commit message', 'chore(Shared): 기여자 구조 정리')
        w.require_valid_commit_text(
            'PR title', 'chore(Shared): 기여자 구조 정리', subject_only=True
        )
        with self.assertRaisesRegex(w.WorkflowError, 'commit policy'):
            w.require_valid_commit_text('Commit message', 'Contributor architecture cleanup')
        with self.assertRaisesRegex(w.WorkflowError, 'commit policy'):
            w.require_valid_commit_text('PR title', 'Invalid title', subject_only=True)

    def test_local_python_checks_are_locale_independent(self):
        with patch.object(w, 'run') as run:
            w.local_checks(self.primary, 'shared')
        python_commands = [
            call.args[1:]
            for call in run.call_args_list
            if call.args[1] == w.sys.executable
        ]
        self.assertTrue(python_commands)
        self.assertTrue(all(command[1:3] == ('-X', 'utf8') for command in python_commands))

    def test_release_manifests_run_the_matching_native_checks(self):
        self.assertEqual(w.required_scopes(['release/macos.json']), ['macos', 'shared'])
        self.assertEqual(w.required_scopes(['release/windows.json']), ['shared', 'windows'])

    def test_workflow_scopes_only_run_affected_platforms(self):
        self.assertEqual(w.required_scopes(['.github/workflows/macos.yml']),
                         ['macos', 'shared'])
        self.assertEqual(w.required_scopes(['.github/workflows/windows-release.yml']),
                         ['shared', 'windows'])
        self.assertEqual(w.required_scopes(['.github/workflows/database.yml']),
                         ['shared'])
        self.assertEqual(w.required_scopes(['.github/workflows/pages.yml']),
                         ['shared', 'web'])
        self.assertEqual(w.required_scopes(['.github/workflows/download-metrics.yml']),
                         ['shared'])

    def test_backend_removal_does_not_require_removed_ci_jobs(self):
        self.assertEqual(w.required_scopes([
            'supabase/migrations/20260915000000_admin_app_store_revenue.sql',
            'services/app-store-verifier/src/server.ts',
            'scripts/supabase/test_concurrency.sh',
        ]), ['shared'])

    def test_platform_workflow_only_changes_do_not_require_app_review(self):
        self.assertFalse(w.app_review_required('macos', ['.github/workflows/macos.yml']))
        self.assertFalse(w.app_review_required('windows', ['.github/workflows/windows.yml']))
        self.assertFalse(w.app_review_required('shared', ['scripts/workflow.py']))

    def test_platform_app_inputs_still_require_app_review(self):
        self.assertTrue(w.app_review_required('macos', ['macos/Sources/SIDEY/App.swift']))
        self.assertTrue(w.app_review_required('windows', ['windows/SIDEY/App.xaml.cs']))
        self.assertTrue(w.app_review_required('windows', ['.github/workflows/windows-release.yml']))
        self.assertTrue(w.app_review_required(
            'macos', ['.github/workflows/macos.yml', 'scripts/package_macos_release.sh']))

    def test_integration_and_scope_logic_changes_run_every_check(self):
        every_scope = {'shared', 'macos', 'windows', 'web'}
        self.assertEqual(set(w.required_scopes(['.github/workflows/integration.yml'])),
                         every_scope)
        self.assertEqual(set(w.required_scopes(['scripts/workflow_ci.py'])), every_scope)


if __name__ == '__main__':
    unittest.main()
