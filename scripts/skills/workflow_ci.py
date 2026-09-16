#!/usr/bin/env python3
"""Resolve affected checks from the complete Git diff and reject missing CI jobs."""
import json
import os
from pathlib import Path
import sys
from workflow import (
    PullRequestValidationError,
    WorkflowError,
    changed_paths,
    git,
    required_scopes,
    root_at,
    validate_message,
    validate_paths,
    validate_pr_body,
    validate_subject,
)


def verify_gate(scopes, needs):
    required = set(scopes) | {'scope', 'shared'}
    failures = {name: needs.get(name, {}).get('result', 'missing') for name in required
                if needs.get(name, {}).get('result') != 'success'}
    if failures:
        raise WorkflowError(f'Required checks did not succeed: {failures}')


def verify_commit_contract(messages, pr_title=None):
    failures = []
    if pr_title is not None:
        violations = validate_subject(pr_title)
        if violations:
            failures.append(f"PR title {pr_title!r}: {'; '.join(violations)}")
    for message in messages:
        violations = validate_message(message)
        if violations:
            subject = message.splitlines()[0] if message.splitlines() else ""
            failures.append(
                f"commit message {subject!r}: {'; '.join(violations)}"
            )
    if failures:
        raise WorkflowError('Commit policy validation failed: ' + ' | '.join(failures))


def verify_pr_contract(root, body, paths):
    try:
        return validate_pr_body(root, body or '', paths)
    except PullRequestValidationError as error:
        raise WorkflowError(f'Pull request template validation failed: {error}') from error


def commit_messages(root, base, revision):
    return [
        message.strip('\r\n')
        for message in git(
            root,
            'log',
            '--format=%B%x00',
            f'{base}..{revision}',
        ).split('\0')
        if message.strip('\r\n')
    ]


def main():
    if sys.argv[1:] == ['gate']:
        needs = json.loads(os.environ['SIDEY_NEEDS'])
        scopes = json.loads(needs.get('scope', {}).get('outputs', {}).get('scopes', '[]'))
        verify_gate(scopes, needs)
        print('All applicable checks succeeded')
        return
    event = json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text())
    pr = event.get('pull_request')
    base = pr['base']['sha'] if pr else event['before']
    revision = pr['head']['sha'] if pr else event['after']
    root = root_at('.')
    paths = changed_paths(root, base, revision)
    if pr:
        verify_commit_contract(
            commit_messages(root, base, revision),
            pr.get('title'),
        )
        verify_pr_contract(root, pr.get('body'), paths)
        validate_paths(pr['head']['ref'], paths)
    else:
        verify_commit_contract(commit_messages(root, base, revision))
    scopes = required_scopes(paths)
    with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
        output.write(f'scopes={json.dumps(scopes)}\n')
    print(json.dumps({'base': base, 'head': revision, 'paths': paths, 'scopes': scopes}, indent=2))


if __name__ == '__main__':
    main()
