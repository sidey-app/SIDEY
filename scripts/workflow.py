#!/usr/bin/env python3
"""Local task ownership, fresh-main checks and reviewed integration for SIDEY.

State is local to the Git common directory. No stash, reset or force push.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
import hashlib
import json
import locale
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time

from validate_commit_message import validate_message, validate_subject


class WorkflowError(RuntimeError):
    pass


def run(root, *args, capture=True):
    result = subprocess.run(args, cwd=root, text=True,
                            stdout=subprocess.PIPE if capture else None,
                            stderr=subprocess.PIPE if capture else None)
    if result.returncode:
        raise WorkflowError(f"{' '.join(args[:4])} failed: {(result.stderr or '').strip()}")
    return (result.stdout or '').rstrip('\n')


def git(root, *args):
    return run(root, 'git', *args)


def root_at(path):
    return Path(git(path, 'rev-parse', '--show-toplevel')).resolve()


def common_dir(root):
    return Path(git(root, 'rev-parse', '--path-format=absolute', '--git-common-dir'))


@contextmanager
def lock(root, name='state'):
    directory = common_dir(root) / 'sidey-workflow'
    directory.mkdir(exist_ok=True)
    with (directory / f'{name}.lock').open('a+b') as stream:
        if os.name == 'nt':
            import msvcrt
            stream.seek(0)
            stream.write(b'0')
            stream.flush()
            stream.seek(0)
            msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
        else:
            import fcntl
            fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        try:
            yield directory
        finally:
            if os.name == 'nt':
                stream.seek(0)
                msvcrt.locking(stream.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                fcntl.flock(stream, fcntl.LOCK_UN)


def atomic_json(path, value):
    descriptor, temporary = tempfile.mkstemp(dir=path.parent, prefix=path.name + '.')
    try:
        with os.fdopen(descriptor, 'w', encoding='utf-8') as stream:
            json.dump(value, stream, indent=2, ensure_ascii=False)
            stream.write('\n')
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def read_state_file(path):
    raw = path.read_bytes()
    try:
        return json.loads(raw.decode('utf-8'))
    except UnicodeDecodeError:
        # getencoding() reports the real locale code page even when Python UTF-8 mode is enabled.
        legacy_encoding = locale.getencoding()
        if legacy_encoding.lower().replace('-', '') == 'utf8':
            raise
        value = json.loads(raw.decode(legacy_encoding))
        atomic_json(path, value)
        return value


def read_state(root):
    with lock(root) as directory:
        path = directory / 'tasks.json'
        return read_state_file(path) if path.exists() else {}


def update_task(root, task_id, value):
    with lock(root) as directory:
        path = directory / 'tasks.json'
        data = read_state_file(path) if path.exists() else {}
        data[task_id] = value
        atomic_json(path, data)


def branch(root):
    return git(root, 'symbolic-ref', '--quiet', '--short', 'HEAD')


def head(root):
    return git(root, 'rev-parse', 'HEAD')


def fetch_main(root):
    # A stale remote-tracking ref is never proof of freshness.
    git(root, 'fetch', '--no-tags', 'origin', '+refs/heads/main:refs/remotes/origin/main')
    return git(root, 'rev-parse', 'refs/remotes/origin/main')


def is_ancestor(root, ancestor, descendant='HEAD'):
    result = subprocess.run(['git', 'merge-base', '--is-ancestor', ancestor, descendant], cwd=root)
    if result.returncode not in (0, 1):
        raise WorkflowError('Cannot determine commit ancestry')
    return result.returncode == 0


def same_tree(root, left, right):
    return git(root, 'rev-parse', f'{left}^{{tree}}') == git(root, 'rev-parse', f'{right}^{{tree}}')


def worktrees(root):
    records = []
    for record in git(root, 'worktree', 'list', '--porcelain').split('\n\n'):
        entry = dict(line.split(' ', 1) if ' ' in line else (line, True)
                     for line in record.splitlines())
        if entry:
            records.append(entry)
    return records


def primary_root(root):
    return Path(worktrees(root)[0]['worktree']).resolve()


def dirty_paths(root):
    # Disable rename detection so both sides of a move cross the boundary guard.
    tracked = git(root, 'diff', '--no-renames', '--name-only', '-z', 'HEAD').split('\0')
    others = git(root, 'ls-files', '--others', '--exclude-standard', '-z').split('\0')
    return sorted(set(tracked + others) - {''})


def changed_paths(root, base, revision='HEAD', dirty=False):
    merge_base = git(root, 'merge-base', base, revision)
    names = git(root, 'diff', '--no-renames', '--name-only', '-z', merge_base, revision).split('\0')
    return sorted((set(names) | set(dirty_paths(root) if dirty else [])) - {''})


def platform_for(path):
    if is_contributor_architecture_path(path):
        return 'shared'
    if (path.startswith(('macos/', 'scripts/macos/')) or
        re.fullmatch(r'scripts/(?:export_macos|install_macos_dev|package_macos_release|release_macos)\.sh', path) or
        re.fullmatch(r'\.github/workflows/macos(?:-[^/]+)?\.yml', path)):
        return 'macos'
    if path.startswith(('windows/', 'scripts/windows/')) or re.fullmatch(r'\.github/workflows/windows(?:-[^/]+)?\.yml', path):
        return 'windows'
    return 'shared'


CONTRIBUTOR_ARCHITECTURE_FILES = frozenset({
    '.githooks/prepare-commit-msg',
    'scripts/setup_codex_attribution.py',
    'scripts/tests/test_codex_attribution.py',
    'scripts/tests/test_contributor_architecture.py',
    'scripts/tests/test_validate_commit_message.py',
    'scripts/validate_commit_message.py',
    'scripts/validate_contributor_architecture.py',
})


def is_contributor_architecture_path(path):
    """Return whether *path* can affect contributors but not shipped artifacts."""

    return (
        path == 'AGENTS.md'
        or path.endswith('/AGENTS.md')
        or path.startswith('.agents/skills/')
        or '/.agents/skills/' in path
        or path in CONTRIBUTOR_ARCHITECTURE_FILES
    )


def validate_paths(branch_name, paths):
    match = re.fullmatch(r'(shared|macos|windows)/[A-Za-z0-9][A-Za-z0-9._/-]*', branch_name)
    if not match:
        raise WorkflowError('Implementation requires shared/*, macos/* or windows/* (never main)')
    platform = match[1]
    invalid = [p for p in paths if platform_for(p) != platform]
    if invalid:
        raise WorkflowError(f'{branch_name} crosses its platform boundary: ' + ', '.join(invalid))
    return platform


def required_scopes(paths):
    if paths and all(is_contributor_architecture_path(path) for path in paths):
        return ['shared']

    result = {'shared'}
    for path in paths:
        platform = platform_for(path)
        if platform != 'shared':
            result.add(platform)
        if path.startswith(('assets/', 'shared/character-throw/')) or path == 'scripts/validate_pixel_assets.py':
            result.update(('macos', 'windows', 'web'))
        if path == 'release/macos.json':
            result.add('macos')
        elif path == 'release/windows.json':
            result.add('windows')
        if path.startswith(('website/', 'scripts/website/')):
            result.add('web')
        if path == 'website/src/pages/ko/terms.md':
            result.add('windows')
        if path == '.github/workflows/integration.yml' or path.startswith('scripts/workflow'):
            result.update(('macos', 'windows', 'web'))
        elif path == '.github/workflows/pages.yml':
            result.add('web')
    return sorted(result)


def app_review_required(platform, paths):
    if platform == 'shared':
        return False
    validation_workflow = f'.github/workflows/{platform}.yml'
    return any(path != validation_workflow for path in paths)


def snapshot(root):
    digest = hashlib.sha256()
    digest.update(head(root).encode())
    digest.update(git(root, 'diff', '--binary', 'HEAD').encode())
    # Include the index: staging after inspection also invalidates the result.
    digest.update(git(root, 'diff', '--cached', '--binary').encode())
    for name in dirty_paths(root):
        path = root / name
        digest.update(name.encode() + b'\0')
        if path.is_symlink():
            digest.update(os.readlink(path).encode())
        elif path.is_file():
            digest.update(path.read_bytes())
        else:
            digest.update(b'<deleted>')
    return digest.hexdigest()


def owned_task(root, task_id):
    task = read_state(root).get(task_id)
    if not task or task['worktree'] != str(root.resolve()) or task['branch'] != branch(root):
        raise WorkflowError('Task does not own this worktree and branch; use start in an isolated worktree')
    return task


def local_checks(root, platform):
    run(root, 'git', 'diff', '--check', capture=False)
    run(root, sys.executable, '-X', 'utf8', '-m', 'unittest', 'discover', '-s', 'scripts/tests', capture=False)
    # Native/DB/web checks are required remotely by the scope-aware integration gate.
    if platform == 'shared':
        run(root, sys.executable, '-X', 'utf8', 'scripts/validate_pixel_assets.py', capture=False)
        run(root, sys.executable, '-X', 'utf8', 'scripts/verify_release_consistency.py',
            '--allow-pending-appcast', '--allow-unreleased-source', capture=False)


def check_task(root, task_id):
    task = owned_task(root, task_id)
    remote = fetch_main(root)
    if not is_ancestor(root, remote):
        raise WorkflowError('Remote main advanced; preserve your changes and run sync before checking')
    paths = changed_paths(root, remote, dirty=True)
    validate_paths(branch(root), paths)
    before = snapshot(root)
    checked_head = head(root)
    local_checks(root, task['platform'])
    if fetch_main(root) != remote or head(root) != checked_head or snapshot(root) != before:
        raise WorkflowError('Source or remote main changed during checks; results invalidated')
    task.update(base=remote, checked={'head': checked_head, 'snapshot': before,
                'base': remote, 'scopes': required_scopes(paths),
                'app_review_required': app_review_required(task['platform'], paths),
                'time': time.time()}, status='checked')
    update_task(root, task_id, task)
    return task


def attest(root, task, remote):
    checked = task.get('checked', {})
    if (checked.get('head') != head(root) or checked.get('snapshot') != snapshot(root)
            or checked.get('base') != remote or not is_ancestor(root, remote)):
        raise WorkflowError('Checks do not match current source/head/base; run check again')


def update_main(root, remote, already_locked=False):
    primary = primary_root(root)

    def apply():
        if branch(primary) != 'main' or dirty_paths(primary):
            raise WorkflowError(f'PR integrated, but primary main is not clean: {primary}; completion pending')
        git(primary, 'merge', '--ff-only', remote)
        if head(primary) != remote:
            raise WorkflowError('Primary main differs from fetched remote main; completion pending')
    if already_locked:
        apply()
    else:
        with lock(root, 'integration'):
            apply()
    return primary


def verify_windows_run(remote, metadata, jobs):
    if (metadata.get('head_sha') != remote or metadata.get('head_branch') != 'main'
            or metadata.get('event') != 'push' or metadata.get('status') != 'completed'
            or metadata.get('conclusion') != 'success'
            or metadata.get('path', '').split('@')[0] != '.github/workflows/integration.yml'):
        raise WorkflowError('Windows app review requires the successful integration run of current main')
    windows = [job for job in jobs if job.get('name') == 'windows']
    if len(windows) != 1 or windows[0].get('conclusion') != 'success':
        raise WorkflowError('Current main did not run the Windows job successfully')
    steps = [step for step in windows[0].get('steps', []) if step.get('name') == 'Run Windows app smoke']
    if len(steps) != 1 or steps[0].get('conclusion') != 'success':
        raise WorkflowError('Windows app startup/preview smoke is missing or did not pass')


def recover_merged_task(root, task, remote):
    # The server may merge successfully even if the client receives a timeout/503.
    checked = task.get('checked', {})
    if (checked.get('head') != head(root) or checked.get('snapshot') != snapshot(root)
            or not checked.get('head')):
        return None
    intent = task.get('merge_intent', {})
    if intent.get('head') != checked['head'] or intent.get('base') != checked.get('base'):
        return None
    prs = json.loads(run(root, 'gh', 'pr', 'list', '--head', branch(root), '--base', 'main',
                         '--state', 'merged', '--json', 'number,headRefOid,mergeCommit,isCrossRepository'))
    matches = [pr for pr in prs if pr['headRefOid'] == checked['head'] and not pr['isCrossRepository']
               and pr.get('mergeCommit') and is_ancestor(root, pr['mergeCommit']['oid'], remote)
               and same_tree(root, checked['head'], pr['mergeCommit']['oid'])
               and squash_intent_matches(root, intent, pr['mergeCommit']['oid'])]
    if len(matches) != 1:
        return None
    pr = matches[0]
    return {**task, 'status': 'integrated', 'pr': str(pr['number']), 'merge': pr['mergeCommit']['oid']}


def parsed_trailers(root, message):
    parsed = subprocess.run(['git', 'interpret-trailers', '--parse'], cwd=root, input=message,
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if parsed.returncode:
        raise WorkflowError(f'Cannot parse commit trailers: {(parsed.stderr or "").strip()}')
    return parsed.stdout.splitlines()


def parsed_coauthors(root, message):
    result = []
    for line in parsed_trailers(root, message):
        match = re.fullmatch(r'Co-authored-by:\s*(.+?)\s*<([^>]+)>', line, re.IGNORECASE)
        if match:
            result.append(f'Co-authored-by: {match[1]} <{match[2]}>')
    return result


def coauthor_trailers(root, messages):
    result = []
    seen = set()
    for message in messages:
        for line in parsed_coauthors(root, message):
            email = re.search(r'<([^>]+)>$', line)[1].casefold()
            if email not in seen:
                seen.add(email)
                result.append(line)
    return result


def commit_messages(root, base, checked_head):
    return [message for message in git(root, 'log', '--format=%B%x00',
                                       f'{base}..{checked_head}').split('\0') if message.strip()]


def require_valid_commit_text(label, value, *, subject_only=False):
    violations = validate_subject(value) if subject_only else validate_message(value)
    if violations:
        raise WorkflowError(f'{label} violates the commit policy: ' + '; '.join(violations))


def pr_body_message(body):
    return f'Squash commit\n\n{body}'


def squash_body(root, body, messages):
    body_message = pr_body_message(body)
    trailers = parsed_trailers(root, body_message)
    clean_body = body.rstrip()
    if trailers:
        lines = clean_body.splitlines()
        separator = max((index for index, line in enumerate(lines) if not line.strip()), default=-1)
        clean_body = '\n'.join(lines[:separator + 1]).rstrip()
    other_trailers = [line for line in trailers
                      if not re.match(r'Co-authored-by:', line, re.IGNORECASE)]
    final_trailers = other_trailers + coauthor_trailers(root, [body_message] + messages)
    if final_trailers:
        return (clean_body + '\n\n' if clean_body else '') + '\n'.join(final_trailers)
    return clean_body


def squash_intent_matches(root, intent, merge_commit):
    subject = git(root, 'show', '-s', '--format=%s', merge_commit)
    body = git(root, 'show', '-s', '--format=%b', merge_commit)
    message = git(root, 'show', '-s', '--format=%B', merge_commit)
    return (subject == intent.get('subject')
            and hashlib.sha256(body.encode()).hexdigest() == intent.get('body_sha256')
            and parsed_coauthors(root, message) == intent.get('coauthors', []))


def finish(root, args):
    task = owned_task(root, args.task)
    if args.paths:
        remote = fetch_main(root)
        attest(root, task, remote)
        paths = dirty_paths(root)
        if sorted(args.paths) != paths:
            raise WorkflowError('--paths must explicitly name every current change; unrelated work must be isolated')
        validate_paths(branch(root), paths)
        if not args.message:
            raise WorkflowError('--message is required when committing explicit paths')
        require_valid_commit_text('Commit message', args.message)
        git(root, 'add', '--', *paths)
        git(root, 'commit', '--only', '-m', args.message, '--', *paths)
        task = check_task(root, args.task)
    if dirty_paths(root):
        raise WorkflowError('Commit this task explicitly with --paths and --message, then recheck')
    remote = fetch_main(root)
    if task.get('status') not in ('integrated', 'main-updated', 'complete'):
        recovered = recover_merged_task(root, task, remote)
        if recovered:
            task = recovered
            update_task(root, args.task, task)
    if task.get('status') in ('integrated', 'main-updated'):
        primary = update_main(root, remote)
        needs_app_review = task.get('checked', {}).get(
            'app_review_required', task['platform'] != 'shared')
        task['status'] = 'main-updated' if needs_app_review else 'complete'
        if args.windows_run:
            if task['platform'] != 'windows':
                raise WorkflowError('--windows-run applies only to an integrated Windows task')
            metadata = json.loads(run(root, 'gh', 'api', f'repos/{{owner}}/{{repo}}/actions/runs/{args.windows_run}'))
            jobs = json.loads(run(root, 'gh', 'api', f'repos/{{owner}}/{{repo}}/actions/runs/{args.windows_run}/jobs?per_page=100'))
            verify_windows_run(remote, metadata, jobs['jobs'])
            if fetch_main(root) != remote or head(primary) != remote or dirty_paths(primary):
                raise WorkflowError('Main changed during Windows app review')
            task.update(status='complete', app_review={'main': remote, 'environment': 'GitHub Actions Windows',
                        'run': args.windows_run, 'url': metadata['html_url'], 'time': time.time()})
        update_task(root, args.task, task)
        return {'status': task['status'], 'main': str(primary), 'sha': remote}
    attest(root, task, remote)
    validate_paths(branch(root), changed_paths(root, remote))
    git(root, 'push', '-u', 'origin', branch(root))
    prs = json.loads(run(root, 'gh', 'pr', 'list', '--head', branch(root), '--base', 'main',
                         '--state', 'open', '--json', 'number,headRefOid,isCrossRepository'))
    if not prs:
        if not args.title or not args.body_file:
            raise WorkflowError('Provide --title and --body-file to create the task PR')
        require_valid_commit_text('PR title', args.title, subject_only=True)
        run(root, 'gh', 'pr', 'create', '--base', 'main', '--head', branch(root),
            '--title', args.title, '--body-file', str(Path(args.body_file).resolve()))
        prs = json.loads(run(root, 'gh', 'pr', 'list', '--head', branch(root), '--base', 'main',
                             '--state', 'open', '--json', 'number,headRefOid,isCrossRepository'))
    if len(prs) != 1 or prs[0]['headRefOid'] != head(root) or prs[0]['isCrossRepository']:
        raise WorkflowError('PR does not identify this exact task head')
    number = str(prs[0]['number'])
    # A named gate must actually exist and succeed; empty required checks never pass.
    checks = json.loads(run(root, 'gh', 'pr', 'checks', number, '--json', 'name,bucket,workflow'))
    gate = [c for c in checks if c['name'] == 'SIDEY integration gate' and c['workflow'] == 'SIDEY integration']
    if len(gate) != 1 or gate[0]['bucket'] != 'pass':
        raise WorkflowError(f'PR #{number} created; integration gate pending/failed. Rerun finish after CI passes')
    run(root, 'gh', 'pr', 'checks', number, '--required')
    checked_head = task['checked']['head']
    checked_base = task['checked']['base']
    details = json.loads(run(root, 'gh', 'pr', 'view', number, '--json', 'title,body'))
    require_valid_commit_text('PR title', details['title'], subject_only=True)
    messages = commit_messages(root, checked_base, checked_head)
    body = squash_body(root, details.get('body') or '', messages)
    expected_coauthors = coauthor_trailers(root, [pr_body_message(details.get('body') or '')] + messages)
    descriptor, body_path = tempfile.mkstemp(prefix='sidey-squash-', suffix='.txt')
    try:
        with os.fdopen(descriptor, 'w', encoding='utf-8') as stream:
            stream.write(body)
        with lock(root, 'integration'):
            remote = fetch_main(root)
            source = json.loads(run(root, 'gh', 'pr', 'view', number,
                                    '--json', 'title,body,headRefOid,baseRefOid,mergeStateStatus'))
            attest(root, task, remote)
            if (source['headRefOid'] != checked_head or source['baseRefOid'] != remote
                    or source['mergeStateStatus'] != 'CLEAN'
                    or source['title'] != details['title'] or source.get('body') != details.get('body')):
                raise WorkflowError('PR head/base/content is not the exact checked and mergeable source')
            task['merge_intent'] = {
                'head': checked_head,
                'base': checked_base,
                'subject': details['title'],
                'body_sha256': hashlib.sha256(body.encode()).hexdigest(),
                'coauthors': expected_coauthors,
                'time': time.time(),
            }
            update_task(root, args.task, task)
            run(root, 'gh', 'pr', 'merge', number, '--squash', '--match-head-commit', checked_head,
                '--subject', details['title'], '--body-file', body_path)
            info = json.loads(run(root, 'gh', 'pr', 'view', number, '--json', 'state,mergeCommit,headRefOid'))
            if info['state'] != 'MERGED' or info['headRefOid'] != checked_head:
                raise WorkflowError('Exact checked head was not confirmed merged')
            remote = fetch_main(root)
            merge_commit = info['mergeCommit']['oid']
            if not is_ancestor(root, merge_commit, remote) or not same_tree(root, checked_head, merge_commit):
                raise WorkflowError('Merged commit does not match the exact checked task tree')
            if not squash_intent_matches(root, task['merge_intent'], merge_commit):
                raise WorkflowError('Squash commit message or co-author attribution differs from the merge intent')
            task.update(status='integrated', pr=number, merge=info['mergeCommit']['oid'])
            update_task(root, args.task, task)
            primary = update_main(root, remote, already_locked=True)
    finally:
        Path(body_path).unlink(missing_ok=True)
    needs_app_review = task.get('checked', {}).get(
        'app_review_required', task['platform'] != 'shared')
    task['status'] = 'main-updated' if needs_app_review else 'complete'
    update_task(root, args.task, task)
    result = {'status': task['status'], 'pr': number, 'main': str(primary), 'sha': remote}
    if needs_app_review:
        result['app'] = 'App verification is a separate required step because app inputs changed'
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', default='.')
    subs = parser.add_subparsers(dest='command', required=True)
    subs.add_parser('doctor')
    start = subs.add_parser('start')
    start.add_argument('task')
    start.add_argument('--platform', choices=['shared', 'macos', 'windows'], required=True)
    start.add_argument('--worktree', required=True)
    start.add_argument('--app', default='SIDEYAppStore', choices=['SIDEYAppStore', 'SIDEY', 'sidey-reals', 'windows'])
    for command in ('sync', 'check', 'finish'):
        sub = subs.add_parser(command)
        sub.add_argument('task', nargs='?')
        if command == 'check':
            sub.add_argument('--ci', action='store_true')
            sub.add_argument('--base')
            sub.add_argument('--head', default='HEAD')
            sub.add_argument('--branch')
        if command == 'finish':
            sub.add_argument('--paths', nargs='+')
            sub.add_argument('--message')
            sub.add_argument('--title')
            sub.add_argument('--body-file')
            sub.add_argument('--windows-run', type=int, help='Complete an integrated Windows task using current-main app smoke CI')
    opener = subs.add_parser('open')
    opener.add_argument('--task', help='Complete an integrated macOS task after verified latest-main app review')
    opener.add_argument('--preview', type=Path)
    opener.add_argument('--offline', action='store_true')
    opener.add_argument('--scheme', default='SIDEYAppStore', choices=['SIDEYAppStore', 'SIDEY', 'sidey-reals'])
    args = parser.parse_args(argv)
    root = root_at(args.repo)
    if args.command == 'doctor':
        try:
            remote = fetch_main(root)
            freshness = 'verified'
        except WorkflowError:
            remote, freshness = None, 'unverified: remote fetch failed'
        entries = worktrees(root)
        for entry in entries:
            path = Path(entry['worktree'])
            entry['exists'] = path.exists()
            entry['changes'] = dirty_paths(path) if path.exists() else None
            entry['included_in_main'] = is_ancestor(root, entry['HEAD'], remote) if remote else None
        result = {'remote_main': remote, 'freshness': freshness, 'worktrees': entries}
    elif args.command == 'start':
        if not re.fullmatch(r'[a-z0-9][a-z0-9._-]*', args.task):
            raise WorkflowError('Task ID must contain lowercase letters, digits, dots, underscores or hyphens')
        remote = fetch_main(root)
        destination = Path(args.worktree).resolve()
        name = f'{args.platform}/{args.task}'
        with lock(root) as directory:
            path = directory / 'tasks.json'
            data = read_state_file(path) if path.exists() else {}
            if args.task in data or any(t['worktree'] == str(destination) for t in data.values()):
                raise WorkflowError('Task/worktree already registered; resume using sync/check')
            if destination.exists():
                raise WorkflowError('start requires a new worktree directory; existing work is preserved')
            git(root, 'worktree', 'add', '-b', name, str(destination), remote)
            data[args.task] = {'worktree': str(destination), 'branch': name, 'platform': args.platform,
                               'app': args.app, 'base': remote, 'status': 'started'}
            atomic_json(path, data)
        result = data[args.task]
    elif args.command == 'sync':
        task = owned_task(root, args.task)
        remote = fetch_main(root)
        if dirty_paths(root):
            raise WorkflowError('Preserve changes in an explicit task commit before sync; no automatic stash')
        validate_paths(branch(root), changed_paths(root, remote))
        git(root, 'merge', '--no-edit', remote)
        task.update(base=remote, status='started')
        task.pop('checked', None)
        update_task(root, args.task, task)
        result = task
    elif args.command == 'check' and args.ci:
        if not args.base or not args.branch:
            raise WorkflowError('CI requires explicit --base and --branch')
        paths = changed_paths(root, args.base, args.head)
        validate_paths(args.branch, paths)
        result = {'paths': paths, 'scopes': required_scopes(paths)}
    elif args.command == 'check':
        result = check_task(root, args.task)
    elif args.command == 'finish':
        result = finish(root, args)
    else:
        if args.task and (args.offline or args.preview):
            raise WorkflowError('Task completion requires latest main; previews remain incomplete')
        if args.offline and not args.preview:
            raise WorkflowError('Offline mode requires an explicit --preview worktree')
        target = root_at(args.preview) if args.preview else primary_root(root)
        if not args.offline:
            remote = fetch_main(root)
            if not args.preview:
                target = update_main(root, remote)
            elif not is_ancestor(target, remote):
                raise WorkflowError('Preview is behind current remote main; sync first or explicitly use --offline')
        script = target / 'scripts/macos/open_current.sh'
        if not script.exists():
            raise WorkflowError('macOS verified opener is not installed at this revision; app was not opened')
        command = [str(script), '--worktree', str(target), '--scheme', args.scheme]
        if args.offline:
            command.append('--offline')
        task = read_state(root).get(args.task) if args.task else None
        if args.task and (not task or task['status'] != 'main-updated' or task['platform'] != 'macos'
                          or task['app'] != args.scheme or not is_ancestor(root, task['checked']['head'], remote)):
            raise WorkflowError('Task must be integrated and awaiting its selected macOS app review')
        run(target, *command, capture=False)
        if task:
            if fetch_main(root) != remote or head(target) != remote:
                raise WorkflowError('Main changed during review; task completion remains pending')
            task.update(status='complete', app_review={'main': remote, 'scheme': args.scheme,
                        'source': str(target), 'time': time.time()})
            update_task(root, args.task, task)
        result = {'target': str(target), 'freshness': 'unverified' if args.offline else 'verified'}
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (WorkflowError, OSError, ValueError) as error:
        print(f'workflow: {error}', file=sys.stderr)
        sys.exit(1)
