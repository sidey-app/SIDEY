# 배포와 제공 채널

## 공개 상태의 source of truth

현재 공개 version과 channel은 [`release/macos.json`](../../release/macos.json)과
[`release/windows.json`](../../release/windows.json)이 소유한다. Release note,
artifact name, website download metadata와 update manifest는 여기서 파생하거나 일치
여부를 검사한다. 이 문서에는 version이나 build number를 복제하지 않는다.

Platform의 정확한 build 설정도 prose가 아니라 project source를 따른다.

- macOS direct target과 Mac App Store target의 version/build는
  [`macos/SIDEY.xcodeproj/project.pbxproj`](../../macos/SIDEY.xcodeproj/project.pbxproj)
  에 있다.
- Windows target framework, minimum OS contract와 binary version은
  [`windows/src/Sidey.App/Sidey.App.csproj`](../../windows/src/Sidey.App/Sidey.App.csproj)
  및 관련 project files에 있다.

## macOS

Developer ID 직접 배포판은 공증 DMG로 설치하고 서명된 Sparkle archive/feed로
업데이트한다. Homebrew Cask는 같은 공증 artifact를 가리킨다. Mac App Store판은 별도
product로 빌드하며 App Store가 설치와 update를 담당한다. 두 distribution은 source를
공유하지만 identity, storage, commerce, entitlement와 signing boundary를 공유하지
않는다.

App Store 후보 version/build가 존재해도 공개 manifest나 direct release가 자동으로
바뀌지 않으며, archive 생성이 submission 또는 review completion을 뜻하지 않는다.

## Windows

Windows는 native app, launcher, assets와 필요한 installer helper를 Setup EXE로
배포한다. Installer는 필요한 shared runtime을 검증하고 기존 설치를 보존할 수 있는
transaction boundary에서 update한다. 새 공개 artifact, update metadata와 release note는
Windows release manifest와 같은 version을 사용한다.

## 공개 웹과 release note

공식 website는 공개 release artifact를 확인하고 실제 hash에서 download metadata를
생성한다. `docs/releases/`는 사용자에게 보이는 각 platform release 결과를 기록하지만
현재 version의 source는 아니다. Store upload, public release, website deployment와
backend deployment는 서로 별도 작업이며 각각 명시적인 승인과 evidence가 필요하다.

반복 가능한 준비·검증·게시 순서는 [release operation](../operations/release.md)을 따른다.
