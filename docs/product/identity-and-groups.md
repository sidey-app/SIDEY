# Identity와 그룹

## 계정

- 정상 계정은 Google 또는 Apple identity를 가진 provider-independent SIDEY UUID다.
  같은 provider subject로 로그인하면 플랫폼과 관계없이 같은 UUID를 사용한다.
- 신규 익명 계정은 만들지 않는다. 이전 익명 계정은 기존 credential과 새로운
  Google 또는 Apple 인증을 서버가 확인한 뒤 같은 UUID로 claim한다. 완료 전에는
  일반 서비스와 구매를 사용할 수 없다.
- 계정 연결·해제는 해당 provider의 새로운 인증을 요구한다. 다른 사용자에게 연결된
  identity나 마지막 남은 identity 해제는 서버가 거부한다. 이메일이 같아도 자동 병합하지 않는다.
- SIDEY access token과 회전하는 refresh token을 OS 보안 저장소에 보관한다.
  여러 기기 session을 허용하며 현재 기기 로그아웃과 모든 기기 로그아웃을 구분한다.
  폐기된 session의 기존 WebSocket도 종료된다.
- Apple 로그인 identity와 App Store 거래 소유권은 별도다. 기존 구매의 계정 binding은
  서버 거래 검증 규칙을 따르며 로그인만으로 임의 변경하지 않는다.

App Store 계정 삭제는 방 탈퇴, 필요한 owner 이전, 개인 데이터 제거와 인증 사용자
삭제를 수행하지만 구매 환불을 뜻하지 않는다. 유효한 비소모성 Apple 구매는 Apple
구매 계정과 서버 검증 결과에 따라 새 SIDEY 계정에서 복원될 수 있다.

## 그룹

그룹은 invite-only private room이다. 방당 최대 열두 명, 사용자당 최대 다섯 방을
허용하고 한 번에 한 방만 overlay에 표시한다. Membership, 정원, 방 수 제한, owner만
가능한 관리 작업은 서버가 transaction 안에서 확인한다. 닉네임과 캐릭터 선택은 같은
방 안에서 중복될 수 있으며 UUID가 실제 식별자다.

모든 member는 방을 나갈 수 있다. Owner가 나가고 member가 남아 있으면 서버가 owner를
joined_at, user_id 순서의 가장 오래된 member에게 이전하며 마지막 member가 나가면
방과 그 메시지를 삭제한다. 이름 변경, 추방과 삭제도
서버 권한 확인 뒤 반영한다.

Invite code는 충분한 난수로 만들고 평문을 database에 저장하지 않는다. 클라이언트에는
join에 필요한 invite만 전달하며 검증용 hash·pepper를 노출하지 않는다. 정확한 backend 구현과 migration은
비공개 backend 저장소의 책임이다.

## 프로필과 장착 상태

닉네임, 캐릭터 및 cosmetic 장착은 account state다. 클라이언트는 서버가 확정한
profile과 활성 entitlement만 표시하며 요청 중인 local selection을 성공으로 간주하지
않는다. 소유권이 회수되면 해당 종류의 기본값으로 돌아간다. Commerce와 장착의 자세한
계약은 [commerce.md](commerce.md)를 따른다.
