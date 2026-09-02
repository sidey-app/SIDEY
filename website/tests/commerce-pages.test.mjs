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

test("public policy URLs contain seller details and macOS-only scope", async () => {
  const [store, terms, privacy, refund, sitemap] = await Promise.all([
    read("store.html"),
    read("terms.html"),
    read("privacy.html"),
    read("refund.html"),
    read("sitemap.xml"),
  ]);

  for (const document of [store, terms, privacy, refund]) {
    assert.ok(document.includes("싸이디(SIDEY)"));
    assert.ok(document.includes("류태현"));
    assert.ok(document.includes("ryu200112@gmail.com"));
  }
  const publishedPolicies = [store, terms, privacy, refund].join("\n");
  assert.ok(publishedPolicies.includes("388-53-01259"));
  assert.ok(publishedPolicies.includes("경기도 용인시 기흥구 서천동로21번길 20-6"));
  assert.ok(publishedPolicies.includes("신고 면제(간이과세자)"));
  assert.ok(store.includes("macOS 전용"));
  assert.ok(store.includes("Windows 릴리스는 구매와 별빛 우파루파 원격 렌더링을 모두 지원하지 않습니다"));
  assert.ok(refund.includes("단순 변심에 따른 청약철회는 제한"));
  assert.ok(refund.includes("법정 사유"));
  for (const fixedPolicyURL of ["store.html", "terms.html", "privacy.html", "refund.html"]) {
    assert.ok(sitemap.includes(`https://sidey-app.github.io/SIDEY/${fixedPolicyURL}`));
  }
});
