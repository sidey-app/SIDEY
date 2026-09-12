#!/usr/bin/env python3
"""Local task ownership, fresh-main checks and reviewed integration for SIDEY.

State is local to the Git common directory. No stash, reset or force push.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time


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
        with os.fdopen(descriptor, 'w') as stream:
            json.dump(value, stream, indent=2, ensure_ascii=False)
            stream.write('\n')
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def read_state(root):
    with lock(root) as directory:
        path = directory / 'tasks.json'
        return json.loads(path.read_text()) if path.exists() else {}


def update_task(root, task_id, value):
    with lock(root) as directory:
        path = directory / 'tasks.json'
        data = json.loads(path.read_text()) if path.exists() else {}
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
    if (path.startswith(('macos/', 'scripts/macos/')) or
        re.fullmatch(r'scripts/(?:export_macos|install_macos_dev|package_macos_release|release_macos)\.sh', path) or
        re.fullmatch(r'\.github/workflows/macos(?:-[^/]+)?\.yml', path)):
        return 'macos'
    if path.startswith(('windows/', 'scripts/windows/')) or re.fullmatch(r'\.github/workflows/windows(?:-[^/]+)?\.yml', path):
        return 'windows'
    return 'shared'


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
    result = {'shared'}
    for path in paths:
        platform = platform_for(path)
        if platform != 'shared':
            result.add(platform)
        if path.startswith(('assets/', 'shared/character-throw/')) or path == 'scripts/validate_pixel_assets.py':
            result.update(('macos', 'windows', 'web', 'server'))
        if path.startswith(('website/', 'scripts/website/')):
            result.add('web')
        if path == 'website/src/pages/ko/terms.md':
            result.add('windows')
        if path.startswith(('supabase/', 'scripts/supabase/')):
            result.update(('database', 'server'))
        if path.startswith('services/'):
            result.add('server')
        if path == 'assets/v1/commerce-catalog.json':
            result.add('database')
        if path.startswith(('.github/workflows/', 'scripts/workflow')):
            result.update(('macos', 'windows', 'web', 'server', 'database'))
    return sorted(result)


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
    run(root, sys.executable, '-m', 'unittest', 'discover', '-s', 'scripts/tests', capture=False)
    # Native/DB/web checks are required remotely by the scope-aware integration gate.
    if platform == 'shared':
        run(root, sys.executable, 'scripts/validate_pixel_assets.py', capture=False)
        run(root, sys.executable, 'scripts/verify_release_consistency.py',
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
                'base': remote, 'scopes': required_scopes(paths), 'time': time.time()}, status='checked')
    update_task(root, task_id, task)
    return task


def attest(root, task, remote):
    checked = task.get('checked', {})
    if (checked.get('head') != head(root) or checked.get('snapshot') != snapshot(root)
            or checked.get('base') != remote or not is_ancestor(root, remote)):
        raise WorkflowError('Checks do not match current source/head/base; run check again')


def update_main(root, remote):
    primary = primary_root(root)
    with lock(root, 'integration'):
        if branch(primary) != 'main' or dirty_paths(primary):
            raise WorkflowError(f'PR integrated, but primary main is not clean: {primary}; completion pending')
        git(primary, 'merge', '--ff-only', remote)
        if head(primary) != remote:
            raise WorkflowError('Primary main differs from fetched remote main; completion pending')
    return primary


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
        git(root, 'add', '--', *paths)
        git(root, 'commit', '--only', '-m', args.message, '--', *paths)
        task = check_task(root, args.task)
    if dirty_paths(root):
        raise WorkflowError('Commit this task explicitly with --paths and --message, then recheck')
    remote = fetch_main(root)
    if task.get('status') == 'integrated':
        primary = update_main(root, remote)
        task['status'] = 'complete'
        update_task(root, args.task, task)
        return {'status': 'complete', 'main': str(primary), 'sha': remote}
    attest(root, task, remote)
    validate_paths(branch(root), changed_paths(root, remote))
    git(root, 'push', '-u', 'origin', branch(root))
    prs = json.loads(run(root, 'gh', 'pr', 'list', '--head', branch(root), '--base', 'main',
                         '--state', 'open', '--json', 'number,headRefOid,isCrossRepository'))
    if not prs:
        if not args.title or not args.body_file:
            raise WorkflowError('Provide --title and --body-file to create the task PR')
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
    attest(root, task, fetch_main(root))
    run(root, 'gh', 'pr', 'merge', number, '--merge', '--match-head-commit', head(root))
    info = json.loads(run(root, 'gh', 'pr', 'view', number, '--json', 'state,mergeCommit,headRefOid'))
    if info['state'] != 'MERGED' or info['headRefOid'] != task['checked']['head']:
        raise WorkflowError('Exact checked head was not confirmed merged')
    remote = fetch_main(root)
    if not is_ancestor(root, head(root), remote):
        raise WorkflowError('Merged task head is not an ancestor of remote main')
    task.update(status='integrated', pr=number, merge=info['mergeCommit']['oid'])
    update_task(root, args.task, task)
    primary = update_main(root, remote)
    task['status'] = 'complete'
    update_task(root, args.task, task)
    return {'status': 'complete', 'pr': number, 'main': str(primary), 'sha': remote,
            'app': 'App verification is a separate required step when app inputs changed'}


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
    opener = subs.add_parser('open')
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
            data = json.loads(path.read_text()) if path.exists() else {}
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
        run(target, *command, capture=False)
        result = {'target': str(target), 'freshness': 'unverified' if args.offline else 'verified'}
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (WorkflowError, OSError, ValueError) as error:
        print(f'workflow: {error}', file=sys.stderr)
        sys.exit(1)
