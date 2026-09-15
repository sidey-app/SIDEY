# 신규 9개 App Store 상품 등록값

사용자가 App Store Connect에서 등록할 한국어 기본값이다. 아래 내용은 [로컬 StoreKit 설정](../SIDEYAppStore.storekit)과 일치하며 실제 등록·가격 변경·심사 제출은 아직 실행하지 않았다.

- 앱: `app.sidey.desktop.appstore`
- 종류: 비소모성(Non-Consumable)
- 한국 가격: 신규 9개 모두 **1,100원**
- 언어: 한국어. 표시명은 2~30자, 설명은 45자 이하로 확인했다. 다른 언어를 추가할 때에도 웹의 긴 설명을 그대로 붙이지 말고 이 길이에 맞춰 준비한다. [Apple 공식 규격](https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-information)
- `character_poop`의 Apple 표시명은 **똥 캐릭터**다. 앱·웹의 이름 **똥**과 Product ID는 유지한다.

| Product ID | Apple 표시명 | 한국어 설명 |
| --- | --- | --- |
| `character_shiba` | 시바견 | 산책은 다녀왔어요. 시바는 그 사실을 인정하지 않아요. |
| `throwable_tennis_ball` | 테니스공 | 던질 사람은 정했어요. 주워 올 사람은 아직이요. |
| `character_duck` | 오리 | 오리발 내미는 데는 자신 있어요. 진짜 오리발이거든요. |
| `character_poop` | 똥 캐릭터 | 누가 불렀는지는 모르겠지만, 일단 나왔어요. |
| `throwable_tissue_ball` | 휴지 뭉치 | 똥휴지인지 아닌지는 모르겠어요. 일단 피하세요! |
| `character_tteokbokki` | 떡볶이 | 순한맛이라더니요. 누구 기준인지는 안 알려줬어요. |
| `throwable_fish_cake_skewer` | 어묵꼬치 | 드시라고 드린 건데 왜 휘두르세요? |
| `character_quokka` | 쿼카 | 항상 웃고 있어요. 방금 잎사귀를 던진 것도 얘예요. |
| `throwable_leaf` | 잎사귀 | 쿼카의 도시락이에요. 던져도 되는지는 안 물어봤어요. |

## 기존 상품

별빛 우파루파의 현재 판매 ID `character_starlight_upalupa_solo`는 한국 가격 **2,200원**으로 맞춘다. 이미 운영 가격이 2,200원이면 중복 변경하지 않는다. 과거 포함 상품 `character_starlight_upalupa`와 모든 복원 ID는 보존하며 별빛 구슬은 별도 **1,100원** 상품이다. 삑삑 오리는 기존 `throwable_squeaky_duck`를 재사용하므로 새 상품을 만들지 않는다.

서버 배포 순서는 [비공개 backend 인계 문서](https://github.com/sidey-app/sidey-backend/blob/main/docs/CONTENT_RELEASE_HANDOFF.md)를 따른다. 서버 상품 33개·Apple 검증 ID 43개를 먼저 맞춘 뒤 상품 등록과 Sandbox 구매·복원·환불을 확인한다. 심사용 스크린샷·메모, 판매 국가와 공개 시점은 사용자가 Connect에서 설정한다. 앱은 실제 StoreKit 현지 가격을 표시한다.
