#!/usr/bin/env python3
# SIDEY Codex attribution hook v1
"""Attribute new Codex-assisted commits without changing human authorship."""

import os
from pathlib import Path
import re
import subprocess
import sys


def git(*args):
    return subprocess.check_output(["git", *args], text=True).strip()


def main():
    mode = os.environ.get("SIDEY_CODEX_COAUTHOR", "")
    if mode == "0" or not (mode == "1" or os.environ.get("CODEX_THREAD_ID")):
        return
    # Reused histories and automatic merge messages are not new authorship.
    if len(sys.argv) > 2 and sys.argv[2] in ("merge", "squash", "commit"):
        return
    if any(
        Path(git("rev-parse", "--git-path", state)).exists()
        for state in (
            "MERGE_HEAD",
            "CHERRY_PICK_HEAD",
            "REBASE_HEAD",
            "rebase-merge",
            "rebase-apply",
        )
    ):
        return
    author = re.search(r"<([^>]+)>", git("var", "GIT_AUTHOR_IDENT"))
    committer = re.search(r"<([^>]+)>", git("var", "GIT_COMMITTER_IDENT"))
    if (
        not author
        or not committer
        or author[1].lower() != committer[1].lower()
    ):
        return
    message = Path(sys.argv[1])
    meaningful = subprocess.check_output(
        ["git", "stripspace", "--strip-comments"],
        input=message.read_text(encoding="utf-8"),
        text=True,
    )
    if not meaningful.strip():
        # Never turn an empty/aborted message into a trailer-only commit.
        return
    trailers = git("interpret-trailers", "--parse", str(message))
    if any(
        re.match(r"co-authored-by\s*:", line, re.I)
        and re.search(r"<codex@openai\.com>\s*$", line, re.I)
        for line in trailers.splitlines()
    ):
        return
    subprocess.run(
        [
            "git",
            "interpret-trailers",
            "--in-place",
            "--if-exists",
            "addIfDifferent",
            "--trailer",
            "Co-authored-by: codex <codex@openai.com>",
            str(message),
        ],
        check=True,
    )


if __name__ == "__main__":
    main()
