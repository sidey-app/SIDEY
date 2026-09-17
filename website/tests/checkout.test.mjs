import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { mountCheckout } from "../public/assets/checkout.js";
import { mountCheckoutResult } from "../public/assets/checkout-result.js";
import { defaultAPIBase, validateAPIBase } from "../public/assets/checkout-api.js";
import { commerceProducts } from "../public/assets/commerce-products.js";

const token = "a".repeat(43);
const productId = Object.keys(commerceProducts)[0];
const paymentId = "sidey-c6fe96cb-d041-4961-84a8-fbd0a1db8964";
const order = {
  orderId: "c6fe96cb-d041-4961-84a8-fbd0a1db8964", productId,
  orderName: commerceProducts[productId].name, amount: 1800, currency: "KRW",
  policyVersion: "2026-06-01", policyNotice: "구매 조건과 환불 안내", requiresConsent: true,
};
const authorization = {
  ...order, requiresConsent: false, storeId: "store-fixture", channelKey: "channel-fixture",
  paymentId, payMethod: "EASY_PAY", portoneCurrency: "CURRENCY_KRW",
  redirectUrl: `https://site.test/SIDEY/checkout-result/#token=${token}`,
};
const ok = payload => ({ ok: true, status: 200, json: async () => payload });
const failure = (status, code) => ({ ok: false, status, json: async () => ({ code }) });

function browser(path = `checkout/#token=${token}`, replies = [ok(order), ok(authorization)]) {
  class Element {
    hidden = false; disabled = true; checked = false; textContent = ""; dataset = {}; listeners = {};
    addEventListener(name, callback) { this.listeners[name] = callback; }
    focus() { this.focused = true; }
  }
  const elements = new Map();
  const document = {
    documentElement: { dataset: { sideyApiBase: defaultAPIBase } },
    querySelector(selector) {
      if (!elements.has(selector)) elements.set(selector, new Element());
      return elements.get(selector);
    },
  };
  let location = new URL(path, "https://site.test/SIDEY/");
  const calls = [], payments = [], redirects = [];
  const window = {
    get location() { location.assign = value => redirects.push(value); return location; },
    history: { replaceState(_state, _title, path) { location = new URL(path, location); } },
    fetch: async (url, options) => {
      assert.equal(location.hash, "", "credential scrubbed before network access");
      assert.equal(location.search, "", "redirect parameters removed from address bar");
      calls.push({ url, ...options, body: JSON.parse(options.body) });
      const response = replies.shift();
      if (response instanceof Error) throw response;
      assert.ok(response, "unexpected request");
      return response;
    },
    PortOne: { requestPayment: async request => { payments.push(request); return { paymentId }; } },
  };
  return { document, window, calls, payments, redirects, el: name => document.querySelector(`#${name}`) };
}

async function consentAndPay(page) {
  page.el("checkout-consent").checked = true;
  page.el("checkout-consent").listeners.change();
  await page.el("checkout-pay").listeners.click();
}

test("prepare uses Spring camelCase order and strips credential before request", async () => {
  const page = browser();
  await mountCheckout(page.document, page.window).ready;
  const { signal, ...request } = page.calls[0];
  assert.ok(signal instanceof AbortSignal);
  assert.deepEqual(request, {
    url: "https://api.sidey.app/api/commerce/checkout", method: "POST",
    headers: { "Content-Type": "application/json" }, body: { token, action: "prepare" },
    credentials: "omit", referrerPolicy: "no-referrer", cache: "no-store", redirect: "error",
  });
  assert.equal(page.el("checkout-order-name").textContent, order.orderName);
  assert.equal(page.el("checkout-amount").textContent, "1,800");
  assert.equal(page.el("checkout-policy-notice").textContent, order.policyNotice);
  assert.equal(page.el("checkout-product").hidden, false);
  assert.equal(page.el("checkout-pay").disabled, true);
  assert.equal(page.el("checkout-meta").textContent, "부가세 포함 · 1회 구매");
});

test("consent is required and SDK receives only server-selected payment values", async () => {
  const page = browser();
  await mountCheckout(page.document, page.window).ready;
  await page.el("checkout-pay").listeners.click();
  assert.equal(page.calls.length, 1);
  assert.equal(page.payments.length, 0);
  assert.equal(page.el("checkout-consent").focused, true);
  await consentAndPay(page);
  assert.deepEqual(page.calls[1].body, { token, action: "authorize", policyVersion: order.policyVersion });
  assert.deepEqual(page.payments[0], {
    storeId: authorization.storeId, channelKey: authorization.channelKey, paymentId,
    orderName: order.orderName, totalAmount: order.amount, currency: "CURRENCY_KRW",
    payMethod: "EASY_PAY", redirectUrl: authorization.redirectUrl,
  });
  const redirect = new URL(page.redirects[0]);
  assert.equal(redirect.searchParams.get("paymentId"), paymentId);
  assert.equal(redirect.searchParams.has("product"), false);
  assert.equal(new URLSearchParams(redirect.hash.slice(1)).get("token"), token);
  assert.equal(page.calls.length, 2, "result page performs server verification");
});

test("query API overrides and malformed credentials never leave the browser", async () => {
  for (const path of [
    `checkout/?api=https://evil.test/api#token=${token}`,
    `checkout/?api=${defaultAPIBase}#token=${token}`, "checkout/#token=short", "checkout/",
  ]) {
    const page = browser(path);
    await mountCheckout(page.document, page.window).ready;
    assert.equal(page.calls.length, 0);
    assert.equal(page.window.location.hash, "");
    assert.equal(page.el("checkout-error").hidden, false);
  }
});

test("build API configuration permits exact HTTPS or local development origins only", () => {
  assert.equal(validateAPIBase("https://payments.example.test/api/"), "https://payments.example.test/api");
  assert.equal(validateAPIBase("http://127.0.0.1:8080/api"), "http://127.0.0.1:8080/api");
  for (const value of ["http://remote.test/api", "https://user:pass@site.test/api", "https://site.test/api?q=1", "https://site.test/api#secret", "https://site.test/", "javascript:alert(1)"]) {
    assert.throws(() => validateAPIBase(value));
  }
});

test("altered order, policy, payment configuration or redirect cannot launch payment", async () => {
  for (const change of [
    { amount: 1 }, { currency: "USD" }, { policyVersion: "different" }, { productId: "unknown" },
    { policyNotice: "changed terms with same policy version" }, { requiresConsent: true },
    { storeId: null }, { paymentId: "" }, { payMethod: "CARD" },
    { redirectUrl: `https://evil.test/SIDEY/checkout-result/#token=${token}` },
    { redirectUrl: `https://site.test/SIDEY/other/#token=${token}` },
    { redirectUrl: `https://site.test/SIDEY/checkout-result/#token=${"b".repeat(43)}` },
  ]) {
    const page = browser(undefined, [ok(order), ok({ ...authorization, ...change })]);
    await mountCheckout(page.document, page.window).ready;
    await consentAndPay(page);
    assert.equal(page.payments.length, 0, JSON.stringify(change));
    assert.equal(page.redirects.length, 0);
  }
});

test("SDK result must match the authorized payment, and cancellation cannot claim success", async () => {
  for (const result of [{ paymentId: "different" }, { code: "USER_CANCEL" }, undefined]) {
    const page = browser();
    page.window.PortOne.requestPayment = async () => result;
    await mountCheckout(page.document, page.window).ready;
    await consentAndPay(page);
    assert.equal(page.redirects.length, 0);
    assert.equal(page.calls.length, 2);
    assert.equal(page.el("checkout-pay").disabled, false);
  }
});

test("checkbox toggles cannot bypass a checkout already in flight", async () => {
  const page = browser();
  let resolvePayment;
  let opened = 0;
  page.window.PortOne.requestPayment = () => {
    opened++;
    return new Promise(resolve => { resolvePayment = resolve; });
  };
  await mountCheckout(page.document, page.window).ready;
  const pending = consentAndPay(page);
  while (!resolvePayment) await new Promise(resolve => setImmediate(resolve));
  page.el("checkout-consent").listeners.change();
  assert.equal(page.el("checkout-pay").disabled, true);
  await page.el("checkout-pay").listeners.click();
  assert.equal(opened, 1);
  resolvePayment({ code: "USER_CANCEL" });
  await pending;
});

test("redirect without legacy result flag is verified by Spring before showing success", async () => {
  const page = browser(`checkout-result/?paymentId=${paymentId}#token=${token}`, [ok({ completed: true, status: "approved" })]);
  await mountCheckoutResult(page.document, page.window);
  assert.equal(page.calls[0].url, defaultAPIBase + "/commerce/complete");
  assert.deepEqual(page.calls[0].body, { token, paymentId });
  assert.equal(page.el("result-title").textContent, "결제가 완료되었어요.");
  assert.match(page.el("result-message").textContent, /구매한 상품/);
});

test("query success or missing credentials cannot assert an entitlement", async () => {
  for (const path of ["checkout-result/?result=success", `checkout-result/?result=success#token=${token}`, `checkout-result/?paymentId=${paymentId}&api=https://evil.test#token=${token}`]) {
    const page = browser(path);
    await mountCheckoutResult(page.document, page.window);
    assert.equal(page.calls.length, 0);
    assert.notEqual(page.el("result-title").textContent, "결제가 완료되었어요.");
  }
});

test("a forged product query cannot claim that a different product was granted", async () => {
  const forgedProduct = Object.keys(commerceProducts)[1];
  const page = browser(`checkout-result/?paymentId=${paymentId}&product=${forgedProduct}#token=${token}`, [ok({ completed: true, status: "approved" })]);
  await mountCheckoutResult(page.document, page.window);
  assert.match(page.el("result-message").textContent, /구매한 상품/);
  assert.equal(page.el("result-message").textContent.includes(commerceProducts[forgedProduct].name), false);
});

test("pending, inconsistent, refunded and failed verification responses never show paid", async () => {
  for (const response of [ok({ completed: false, status: "pending" }), ok({ completed: true, status: "refunded" }), ok({ completed: false, status: "approved" }), ok(null), failure(409, "payment_not_paid"), failure(410, "checkout_expired"), new Error("network unavailable")]) {
    const page = browser(`checkout-result/?result=success&paymentId=${paymentId}#token=${token}`, [response]);
    await mountCheckoutResult(page.document, page.window);
    assert.notEqual(page.el("result-title").textContent, "결제가 완료되었어요.");
  }
  const page = browser(`checkout-result/?paymentId=${paymentId}#token=${token}`, [ok({ completed: false, status: "refunded" })]);
  await mountCheckoutResult(page.document, page.window);
  assert.equal(page.el("result-title").textContent, "환불된 결제입니다.");
});

test("generated checkout pages share a validated configured origin with their CSP", () => {
  const expected = validateAPIBase(process.env.PUBLIC_SIDEY_API_BASE_URL ?? defaultAPIBase);
  for (const route of ["checkout", "checkout-result"]) {
    const html = readFileSync(new URL(`../dist/${route}/index.html`, import.meta.url), "utf8");
    assert.ok(html.includes(`data-sidey-api-base="${expected}"`));
    assert.ok(html.includes(`connect-src ${new URL(expected).origin}`));
    assert.doesNotMatch(html, /supabase|localhost:\*|127\.0\.0\.1:\*/);
    assert.match(html, /name="referrer" content="no-referrer"/);
  }
});


test("provider, backend, policy and rate errors prevent payment and give actionable feedback", async () => {
  for (const [code, status, text] of [
    ["commerce_not_configured", 503, "지금은 결제를"],
    ["commerce_sales_disabled", 503, "지금은 결제를"],
    ["commerce_rate_limited", 429, "잠시 기다린"],
    ["commerce_policy_version_mismatch", 409, "구매 조건이 변경"],
    ["checkout_expired", 410, "사용할 수 없는 주문"],
    ["database_unavailable", 503, "서버에서 결제 상태"],
  ]) {
    const prepare = browser(undefined, [failure(status, code)]);
    await mountCheckout(prepare.document, prepare.window).ready;
    assert.ok(prepare.el("checkout-error-message").textContent.includes(text), code);
    assert.equal(prepare.el("checkout-pay").disabled, true);
    assert.equal(prepare.payments.length, 0);
    const authorize = browser(undefined, [ok(order), failure(status, code)]);
    await mountCheckout(authorize.document, authorize.window).ready;
    await consentAndPay(authorize);
    assert.ok(authorize.el("checkout-status").textContent.includes(text), code);
    assert.equal(authorize.payments.length, 0);
  }
});
