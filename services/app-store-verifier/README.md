# SIDEY App Store verifier

서명된 StoreKit 2 transaction과 App Store Server Notifications V2를 Apple 공식 라이브러리로 검증한 뒤 Supabase의 비공개 commerce 원장에 반영하는 Node 22 서비스다. App Store용 키와 Supabase secret key는 저장소에 두지 않는다.

## Endpoints

- `POST /v1/app-store/transactions`: Supabase Bearer token과 `signedTransactionInfo` 필요
- `POST /v1/app-store/notifications`: Apple의 `signedPayload` 필요
- `POST /v1/accounts/delete`: Supabase Bearer token, fresh Apple `identityToken`, `authorizationCode`, raw `nonce` 필요
- `GET /health`: 프로세스 상태만 반환

Production과 Sandbox는 서로 다른 Cloud Run 서비스와 Secret Manager secret을 사용한다. App Store Connect의 Production/Sandbox 알림 URL은 각각 해당 서비스의 `/v1/app-store/notifications`로 지정한다.


## Google Cloud Shell에서 최신 main 배포

Google Cloud Console에서 Cloud Shell을 연 뒤 아래 명령을 실행한다. 현재 Sandbox URL의 프로젝트 번호 `802687666602`를 실제 프로젝트 ID로 조회하고, 두 기존 서비스가 있는지 확인한 후 각각 소스를 배포한다. 환경변수·Secret Manager 연결·서비스 계정·IAM 설정은 변경하지 않는다. 기존 설정이 없는 새 서비스를 만드는 용도로 사용하지 않는다.

```sh
set -eu
SIDEY_GCP_PROJECT=$(gcloud projects describe 802687666602 --format='value(projectId)')
SIDEY_GCP_REGION=asia-northeast3

gcloud run services describe sidey-app-store-verifier-sandbox \
  --project="$SIDEY_GCP_PROJECT" --region="$SIDEY_GCP_REGION" --format='value(status.url)'
gcloud run services describe sidey-app-store-verifier-production \
  --project="$SIDEY_GCP_PROJECT" --region="$SIDEY_GCP_REGION" --format='value(status.url)'

SIDEY_DEPLOY_DIR=$(mktemp -d)
git clone --depth 1 --branch main https://github.com/sidey-app/SIDEY.git "$SIDEY_DEPLOY_DIR"
cd "$SIDEY_DEPLOY_DIR"
git rev-parse HEAD

gcloud run deploy sidey-app-store-verifier-sandbox \
  --project="$SIDEY_GCP_PROJECT" --region="$SIDEY_GCP_REGION" \
  --source=services/app-store-verifier --quiet

gcloud run deploy sidey-app-store-verifier-production \
  --project="$SIDEY_GCP_PROJECT" --region="$SIDEY_GCP_REGION" \
  --source=services/app-store-verifier --quiet

for SIDEY_SERVICE in sidey-app-store-verifier-sandbox sidey-app-store-verifier-production; do
  SIDEY_SERVICE_URL=$(gcloud run services describe "$SIDEY_SERVICE" \
    --project="$SIDEY_GCP_PROJECT" --region="$SIDEY_GCP_REGION" --format='value(status.url)')
  curl --fail --silent --show-error "$SIDEY_SERVICE_URL/health"
  printf '\n'
done
```

배포할 소스는 `character_monkey_solo_4`를 포함한 현재·과거 Apple 상품 ID 34개를 검증한다. DB에는 `20260912130000_monkey_fourth_app_store_offer.sql`까지 필요한 migration이 적용되어 있어야 한다. Cloud Run 배포는 Supabase migration을 실행하지 않는다. `/health` 성공은 프로세스 생존 확인이며 실제 구매·복원·환불 검증을 대신하지 않는다.
