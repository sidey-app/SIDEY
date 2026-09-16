# Identity와 그룹

## 계정

- macOS 직접 배포판은 기존 익명 Supabase session을 복구하며, 지원되는 개발 commerce
  흐름에서만 같은 사용자 UUID에 외부 identity를 연결한다.
- Mac App Store판은 Sign in with Apple과 전용 Keychain 경계를 사용한다. 직접 배포판
  계정과 App Store 계정은 자동 이전하거나 병합하지 않는다. 같은 사람이 두 계정으로
  한 방에 참가하면 별도 member로 센다.
- Windows는 저장된 익명 session을 먼저 복구하고 신규 설치에서만 새 익명 계정을
  만든다. token과 재사용이 필요한 invite code는 Windows Credential Manager에만
  보관한다.
- 서로 다른 플랫폼의 별도 사용자 UUID 사이에는 account migration을 제공하지 않는다.

App Store 계정 삭제는 방 탈퇴, 필요한 owner 이전, 개인 데이터 제거와 인증 사용자
삭제를 수행하지만 구매 환불을 뜻하지 않는다. 유효한 비소모성 Apple 구매는 Apple
구매 계정과 서버 검증 결과에 따라 새 SIDEY 계정에서 복원될 수 있다.

## 그룹

그룹은 invite-only private room이다. 방당 최대 열두 명, 사용자당 최대 다섯 방을
허용하고 한 번에 한 방만 overlay에 표시한다. Membership, 정원, 방 수 제한, owner만
가능한 관리 작업은 서버가 transaction 안에서 확인한다. 닉네임과 캐릭터 선택은 같은
방 안에서 중복될 수 있으며 UUID가 실제 식별자다.

모든 member는 방을 나갈 수 있다. Owner가 나가고 member가 남아 있으면 서버가 owner를
이전하며 마지막 member가 나가면 방과 그 메시지를 삭제한다. 이름 변경, 추방과 삭제도
서버 권한 확인 뒤 반영한다.

Invite code는 충분한 난수로 만들고 평문을 database에 저장하지 않는다. 공개 API와
Realtime row는 검증용 secret을 노출하지 않는다. 정확한 backend 구현과 migration은
비공개 backend 저장소의 책임이다.

## 프로필과 장착 상태

닉네임, 캐릭터 및 cosmetic 장착은 account state다. 클라이언트는 서버가 확정한
profile과 활성 entitlement만 표시하며 요청 중인 local selection을 성공으로 간주하지
않는다. 소유권이 회수되면 해당 종류의 기본값으로 돌아간다. Commerce와 장착의 자세한
계약은 [commerce.md](commerce.md)를 따른다.
