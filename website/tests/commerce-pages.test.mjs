import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("checkout starts without consent and keeps payment disabled", async () => {
  const html = await read("checkout.html");
  const checkbox = html.match(/<input id="checkout-consent"[^>]*>/)?.[0] ?? "";
  const payButton = html.match(/<button id="checkout-pay"[^>]*>/)?.[0] ?? "";

  assert.ok(checkbox.includes('type="checkbox"'));
  assert.ok(!checkbox.includes("checked"));
  assert.ok(payButton.includes("disabled"));
  for (const fixedPolicyURL of ["./store.html", "./terms.html", "./privacy.html", "./refund.html"]) {
    assert.ok(html.includes(fixedPolicyURL));
  }
});

test("checkout records policy consent before opening PortOne", async () => {
  const script = await read("assets/checkout.js");
  const authorizeIndex = script.indexOf('action: "authorize"');
  const portOneIndex = script.indexOf("window.PortOne.requestPayment");

  assert.ok(authorizeIndex >= 0);
  assert.ok(portOneIndex > authorizeIndex);
  assert.ok(script.includes('action: "prepare"'));
  assert.ok(script.includes("policy_version: prepared.policy_version"));
  assert.ok(script.includes("if (!consent.checked)"));
  assert.ok(script.includes("window.history.replaceState"));
  assert.ok(script.includes('consent.addEventListener("change"'));
});

test("checkout uses PortOne V2 EASY_PAY with server-owned identifiers", async () => {
  const [html, script] = await Promise.all([read("checkout.html"), read("assets/checkout.js")]);

  assert.ok(html.includes("https://cdn.portone.io/v2/browser-sdk.js"));
  for (const mapping of [
    "storeId: config.store_id",
    "channelKey: config.channel_key",
    "paymentId: config.payment_id",
    "totalAmount: config.amount",
    "currency: config.portone_currency",
    "payMethod: config.pay_method",
    "redirectUrl: config.redirect_url",
  ]) {
    assert.ok(script.includes(mapping), `missing PortOne mapping: ${mapping}`);
  }
  assert.ok(script.includes('config.pay_method === "EASY_PAY"'));
  assert.ok(!`${html}\n${script}`.match(/TossPayments|tosspayments|토스페이먼츠/));
});

test("Korean landing links to the separate store and keeps seller details in the footer", async () => {
  const [korean, english] = await Promise.all([read("index.html"), read("en/index.html")]);

  assert.ok(korean.includes('href="./store.html"'));
  assert.ok(!korean.includes('data-product-id="character_starlight_upalupa"'));
  for (const requiredCopy of [
    "./store.html",
    "싸이디(SIDEY)",
    "388-53-01259",
    "ryu200112@gmail.com",
  ]) {
    assert.ok(korean.includes(requiredCopy), `missing Korean landing copy: ${requiredCopy}`);
  }

  for (const commerceURL of ["store.html", "terms.html", "privacy.html", "refund.html"]) {
    assert.ok(!english.includes(commerceURL));
  }
});

test("Windows production release is staged for verified MSI deployment", async () => {
  const [korean, english, latest, compatibility] = await Promise.all([
    read("index.html"),
    read("en/index.html"),
    read("windows-latest.json").then(JSON.parse),
    read("windows/update.json").then(JSON.parse),
  ]);
  const installerURL = "https://github.com/sidey-app/SIDEY/releases/download/windows-v1.0.5/SIDEY-Windows-x64-v1.0.5.msi";

  assert.deepEqual(latest, compatibility);
  assert.equal(latest.channel, "production");
  assert.equal(latest.version, "1.0.5");
  assert.equal(latest.tag, "windows-v1.0.5");
  assert.equal(latest.installer_url, installerURL);
  assert.equal(latest.sha256, null);
  for (const page of [korean, english]) {
    assert.ok(page.includes('id="windows-hero-download-action"'));
    assert.ok(page.includes('id="windows-download-action"'));
    assert.ok(page.includes("v1.0.5"));
    assert.ok(!page.includes("Setup.exe"));
    assert.ok(!page.includes("SmartScreen"));
  }
  assert.ok(korean.includes("한 번 직접 설치"));
  assert.ok(english.includes("install this MSI manually once"));
});

test("store renders a stable four-product catalog without duplicated footer details", async () => {
  const [store, styles] = await Promise.all([read("store.html"), read("assets/styles.css")]);
  for (const name of ["별빛 우파루파", "아기 기니피그", "아기 원숭이", "아기 친칠라"]) {
    assert.ok(store.includes(name), `missing product: ${name}`);
  }
  assert.equal(store.match(/class="store-catalog-card"/g)?.length, 4);
  assert.equal(store.match(/990원/g)?.length, 3);
  assert.equal(store.match(/1,900원/g)?.length, 1);
  assert.ok(store.includes("macOS SIDEY 앱"));
  assert.ok(store.includes("꾸미기·상점"));
  assert.ok(!store.includes('id="privacy"'));
  assert.ok(!store.includes("판매자 정보"));
  assert.equal(store.match(/<dt>/g)?.length ?? 0, 0);
  assert.ok(store.includes('class="store-page"'));
  assert.ok(store.includes("단순 변심 환불 불가"));
  for (const internalCopy of ["출시 예정", "production", "Sidey-dev", "SIDEY-staging", "테스트 채널"]) {
    assert.ok(!store.includes(internalCopy), `store exposes internal rollout copy: ${internalCopy}`);
  }
  assert.ok(styles.includes(".store-catalog"));
  assert.ok(styles.includes(".store-page .section h2"));
  assert.ok(styles.includes("word-break: keep-all"));
  assert.ok(styles.includes("text-wrap: balance"));
  assert.ok(styles.includes(".seller-details > div"));
  assert.ok(styles.includes("grid-template-columns: 132px minmax(0, 1fr)"));
  assert.ok(styles.includes("grid-template-columns: 104px minmax(0, 1fr)"));
});

test("public policy URLs keep seller scope and PortOne refund terms", async () => {
  const [landing, store, terms, privacy, refund, sitemap, migration] = await Promise.all([
    read("index.html"),
    read("store.html"),
    read("terms.html"),
    read("privacy.html"),
    read("refund.html"),
    read("sitemap.xml"),
    read("../supabase/migrations/20260903000000_commerce_refund_policy_v2.sql"),
  ]);

  for (const document of [terms, privacy, refund]) {
    assert.ok(document.includes("싸이디(SIDEY)"));
    assert.ok(document.includes("ryu200112@gmail.com"));
    assert.ok(!document.includes("010-9270-2973"));
  }
  assert.ok(!store.includes("싸이디(SIDEY)"));
  assert.ok(!store.includes("ryu200112@gmail.com"));
  const publishedPolicies = [landing, terms, privacy, refund].join("\n");
  assert.ok(publishedPolicies.includes("388-53-01259"));
  assert.ok(publishedPolicies.includes("경기도 용인시 기흥구 서천동로21번길 20-6"));
  assert.ok(publishedPolicies.includes("신고 면제(간이과세자)"));
  assert.ok(`${terms}\n${refund}`.includes("PortOne"));
  assert.ok(terms.includes("macOS SIDEY 앱의 꾸미기·상점"));
  assert.ok(!terms.includes("production 판매"));
  for (const document of [landing, store, terms, refund]) {
    assert.ok(!document.includes("7일 이내"));
    assert.ok(!document.includes("사용 여부와 관계없이"));
  }
  assert.ok(refund.includes("제공 시작 후 단순 변심 환불 불가"));
  assert.ok(refund.includes("정책 버전 2026-09-03-portone-v2"));
  assert.ok(migration.includes("policy_version = '2026-09-03-portone-v2'"));
  assert.ok(migration.includes("제공 시작 뒤 단순 변심에 따른 청약철회와 환불은 불가합니다"));
  for (const fixedPolicyURL of ["store.html", "terms.html", "privacy.html", "refund.html"]) {
    assert.ok(sitemap.includes(`https://sidey-app.github.io/SIDEY/${fixedPolicyURL}`));
  }
});

test("checkout is token-only and completion trusts a server re-query", async () => {
  const [html, checkout, result] = await Promise.all([
    read("checkout.html"),
    read("assets/checkout.js"),
    read("assets/checkout-result.js"),
  ]);
  const copy = `${html}\n${checkout}\n${result}`;

  assert.ok(html.includes('name="robots" content="noindex, nofollow"'));
  assert.ok(checkout.includes("new URLSearchParams(window.location.hash.slice(1))"));
  assert.ok(checkout.includes('request("commerce-complete"'));
  assert.ok(result.includes("/commerce-complete"));
  assert.ok(copy.includes("PortOne"));
  assert.ok(copy.includes("결제 상태를 확인"));
  assert.ok(!copy.match(/TossPayments|tosspayments|토스페이먼츠/));
});
