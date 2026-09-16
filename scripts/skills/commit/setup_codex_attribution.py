#!/usr/bin/env python3
"""Install SIDEY's Codex-only hook once per clone, shared by its worktrees."""

from pathlib import Path
import subprocess

MARKER = b"# SIDEY Codex attribution hook v1"


def install():
    source = Path(__file__).resolve().with_name("prepare_commit_msg.py")
    config = subprocess.run(
        ["git", "config", "--get", "core.hooksPath"],
        capture_output=True,
        text=True,
    )
    if config.returncode not in (0, 1):
        raise SystemExit(config.stderr)
    if config.returncode == 0:
        raise SystemExit(
            "기존 core.hooksPath를 보존합니다. 해당 훅 관리자에서 SIDEY 훅을 명시적으로 연결하세요."
        )
    common = Path(
        subprocess.check_output(
            ["git", "rev-parse", "--git-common-dir"], text=True
        ).strip()
    ).resolve()
    destination = common / "hooks/prepare-commit-msg"
    if destination.is_symlink() or (
        destination.exists()
        and MARKER not in destination.read_bytes().splitlines()[:3]
    ):
        raise SystemExit(
            "기존 prepare-commit-msg 훅을 보존합니다. 먼저 두 훅의 연결 방식을 검토하세요."
        )
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(source.read_bytes())
    destination.chmod(0o755)
    print(
        f"설치 완료: {destination}\n"
        "이 clone의 모든 worktree에 적용됩니다. "
        "Git 작성자·다른 훅·설정은 유지합니다."
    )


if __name__ == "__main__":
    install()
