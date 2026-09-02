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
  for (const fixedPolicyURL of ["./terms.html", "./privacy.html", "./refund.html"]) {
    assert.ok(html.includes(fixedPolicyURL));
  }
});

test("checkout records explicit consent before initializing Toss", async () => {
  const script = await read("assets/checkout.js");
  const acceptedIndex = script.indexOf('accepted: true');
  const tossIndex = script.indexOf("window.TossPayments(config.client_key)");

  assert.ok(acceptedIndex >= 0);
  assert.ok(tossIndex > acceptedIndex);
  assert.ok(script.includes('action: "prepare"'));
  assert.ok(script.includes('action: "consent"'));
  assert.ok(script.includes("if (!consent.checked)"));
  assert.ok(script.includes("window.history.replaceState"));
  assert.ok(script.includes("config.policy_version === preparedOrder.policy_version"));
});

test("checkout uses the live basic payment UI with standard easy pay methods", async () => {
  const script = await read("assets/checkout.js");

  assert.ok(script.includes('variantKey: { paymentMethod: "sideyCheckout" }'));
  assert.ok(!script.includes("renderPaymentWindow();"));
});

test("Korean landing links to the separate store and keeps commerce details in the footer", async () => {
  const [korean, english] = await Promise.all([read("index.html"), read("en/index.html")]);

  assert.ok(korean.includes('<a class="nav-tab" href="./store.html">상점</a>'));
  assert.ok(!korean.includes('data-product-id="character_starlight_upalupa"'));
  for (const requiredCopy of [
    "./store.html",
    "배송일자",
    "디지털 상품으로 결제 완료 즉시 사용 가능",
    "교환·환불",
    "싸이디(SIDEY)",
    "388-53-01259",
    "010-9270-2973",
    "ryu200112@gmail.com",
    "경기도 용인시 기흥구 서천동로21번길 20-6",
    "류태현",
    "신고 면제(간이과세자)",
  ]) {
    assert.ok(korean.includes(requiredCopy), `missing Korean landing copy: ${requiredCopy}`);
  }

  for (const commerceURL of ["store.html", "terms.html", "privacy.html", "refund.html"]) {
    assert.ok(!english.includes(commerceURL));
  }
  assert.ok(english.includes("ryu200112@gmail.com"));
  assert.ok(english.includes("388-53-01259"));
  assert.ok(!english.includes("010-9270-2973"));
  assert.ok(!english.includes("류태현"));
  assert.ok(!english.includes("서천동로21번길"));
});

test("store renders character products as an extensible square card grid", async () => {
  const [store, styles] = await Promise.all([read("store.html"), read("assets/styles.css")]);

  assert.ok(store.includes('class="store-catalog-grid"'));
  assert.equal(store.match(/data-product-id="character_starlight_upalupa"/g)?.length, 1);
  assert.ok(store.includes('class="store-character-card"'));
  assert.ok(styles.includes("grid-template-columns: repeat(auto-fill"));
  assert.match(styles, /\.store-character-card\s*\{[^}]*aspect-ratio:\s*1;/s);
});

test("public policy URLs omit personal contact details and keep the required business scope", async () => {
  const [store, terms, privacy, refund, sitemap] = await Promise.all([
    read("store.html"),
    read("terms.html"),
    read("privacy.html"),
    read("refund.html"),
    read("sitemap.xml"),
  ]);

  for (const document of [store, terms, privacy, refund]) {
    assert.ok(document.includes("싸이디(SIDEY)"));
    assert.ok(document.includes("ryu200112@gmail.com"));
    assert.ok(!document.includes("류태현"));
    assert.ok(!document.includes("010-9270-2973"));
  }
  const publishedPolicies = [store, terms, privacy, refund].join("\n");
  assert.ok(publishedPolicies.includes("388-53-01259"));
  assert.ok(publishedPolicies.includes("경기도 용인시 기흥구 서천동로21번길 20-6"));
  assert.ok(publishedPolicies.includes("신고 면제(간이과세자)"));
  assert.ok(store.includes("macOS 전용"));
  assert.ok(store.includes("Windows에서는 구매하거나 사용할 수 없습니다"));
  assert.ok(refund.includes("단순 변심에 따른 청약철회는 제한"));
  assert.ok(refund.includes("법정 사유"));
  assert.ok(refund.includes("정책 버전 2026-09-02-v2"));
  for (const fixedPolicyURL of ["store.html", "terms.html", "privacy.html", "refund.html"]) {
    assert.ok(sitemap.includes(`https://sidey-app.github.io/SIDEY/${fixedPolicyURL}`));
  }
});

test("checkout copy is customer-facing and hides live implementation details", async () => {
  const documents = await Promise.all([
    read("checkout.html"),
    read("store.html"),
    read("terms.html"),
    read("privacy.html"),
    read("refund.html"),
    read("assets/checkout.js"),
    read("assets/checkout-result.js"),
  ]);
  const copy = documents.join("\n");

  for (const internalPhrase of [
    "라이브 결제",
    "SIDEY 서버",
    "서버 결제 확인",
    "정적 성공 화면",
    "반환 URL",
    "비공개 commerce",
  ]) {
    assert.ok(!copy.includes(internalPhrase), `unexpected internal phrase: ${internalPhrase}`);
  }
  assert.ok(copy.includes("결제가 완료되면 구매한 SIDEY 계정에서 별빛 우파루파를 바로 사용할 수 있습니다."));
});
