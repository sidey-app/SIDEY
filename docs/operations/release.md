# Release operation

이 문서는 반복 가능한 공개 release 순서를 요약한다. 실제 version, build와 artifact
이름은 machine-readable source에서 읽으며 이 문서에 고정하지 않는다. Release, store
submission, upload, website deployment와 production backend deployment는 각각 명시적인
사용자 승인이 필요하다.

## 1. 범위와 version 확인

1. Target platform과 실제 shipped diff를 확정한다.
2. [version audit](../../.agents/skills/version-audit/SKILL.md) 절차로 최소 version/build
   변경을 판단한다.
3. Platform project source와 해당 [`release/` manifest](../../release/README.md)를
   일치시킨다. Mac App Store 후보처럼 공개 release와 다른 build는 public manifest를
   앞서 변경하지 않는다.

Commerce 또는 backend contract가 바뀌는 release라면 공개 catalog의 검토된 commit과
backend snapshot provenance를 먼저 확인한다. Backend migration과 배포는 비공개
backend 저장소의 절차로 수행하며 이 저장소에서 대신 실행하지 않는다.

## 2. 검증과 release note

1. 변경 경로에 해당하는 integration check와 platform test를 정확한 candidate commit에
   실행한다.
2. Project version, release manifest, update source, website metadata와 release note의
   일치는 `python3 scripts/skills/verify_release_consistency.py`로 검사한다.
3. [`docs/releases/`](../releases/)의 해당 platform note를
   [release-notes skill](../../.agents/skills/release-notes/SKILL.md)의 commit/PR evidence로
   작성하고 link와 attribution을 검증한다.
4. 서명, 공증, installer 실행, store purchase 또는 실제 장시간 test처럼 수행하지 않은
   검사를 통과했다고 기록하지 않는다.

Candidate source가 검증 뒤 바뀌면 영향을 받는 검사를 다시 실행한다.

## 3. Artifact 생성과 검사

### macOS direct

운영자 Mac에서 [`scripts/release_macos.sh`](../../scripts/release_macos.sh)를 사용한다.
Script가 Developer ID signing, Hardened Runtime, notarization/stapling, DMG와 Sparkle ZIP,
hash 및 download 재검증을 완료해야 한다. Signing 및 Sparkle private key는 repository나
CI log에 넣지 않는다. App Store archive와 submission은 direct release와 별도다.

### Windows

`main`의 수동 [Windows Release workflow](../../.github/workflows/windows-release.yml)를
사용한다. Workflow가 전체 Windows 검사, installer 생성, draft asset 재다운로드와 hash
대조를 한 runner에서 마친 뒤에만 publish한다. Local build나 artifact 존재만으로 공개
release를 대체하지 않는다.

## 4. 게시 후 확인

1. 공개 release에서 내려받은 artifact와 기대 hash를 다시 확인한다.
2. Update feed/manifest와 공식 website가 같은 release manifest에서 파생됐는지 확인한다.
3. Platform release note와 comparison link가 공개 결과와 일치하는지 확인한다.
4. 별도 승인된 경우에만 store submission, website deployment 또는 backend deployment를
   수행하고 각각의 결과를 해당 system에서 검증한다.

과거 특정 release의 시행착오와 일회성 checklist는 Git/PR 및 GitHub Release history에
맡긴다.
