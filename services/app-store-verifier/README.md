# SIDEY App Store verifier

서명된 StoreKit 2 transaction과 App Store Server Notifications V2를 Apple 공식 라이브러리로 검증한 뒤 Supabase의 비공개 commerce 원장에 반영하는 Node 20 서비스다. App Store용 키와 Supabase service role key는 저장소에 두지 않는다.

## Endpoints

- `POST /v1/app-store/transactions`: Supabase Bearer token과 `signedTransactionInfo` 필요
- `POST /v1/app-store/notifications`: Apple의 `signedPayload` 필요
- `POST /v1/accounts/delete`: Supabase Bearer token, fresh Apple `identityToken`, `authorizationCode`, raw `nonce` 필요
- `GET /health`: 프로세스 상태만 반환

Production과 Sandbox는 서로 다른 Cloud Run 서비스와 Secret Manager secret을 사용한다. App Store Connect의 Production/Sandbox 알림 URL은 각각 해당 서비스의 `/v1/app-store/notifications`로 지정한다.
