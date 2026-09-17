export const defaultAPIBase = "https://api.sidey.app/api";

export function validateAPIBase(value) {
  const url = new URL(value);
  const loopback = ["localhost", "127.0.0.1", "[::1]"].includes(url.hostname);
  if ((url.protocol !== "https:" && !(url.protocol === "http:" && loopback)) ||
      url.username || url.password || url.search || url.hash || !/^\/api\/?$/.test(url.pathname)) {
    throw new Error("invalid_checkout_api_base");
  }
  return `${url.origin}/api`;
}

export function checkoutContext(document, window) {
  const query = new URLSearchParams(window.location.search);
  const token = new URLSearchParams(window.location.hash.slice(1)).get("token");
  // Keep the order credential in memory only, including when a link is rejected.
  window.history.replaceState(null, "", window.location.pathname);
  if (query.has("api") || !/^[A-Za-z0-9_-]{43}$/.test(token ?? "")) {
    throw new Error("invalid_checkout_link");
  }
  return { query, token, apiBase: validateAPIBase(document.documentElement.dataset.sideyApiBase) };
}

export async function commerceRequest(window, apiBase, action, body) {
  if (!["checkout", "complete"].includes(action)) throw new Error("invalid_checkout_action");
  const response = await window.fetch(`${apiBase}/commerce/${action}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
    credentials: "omit",
    referrerPolicy: "no-referrer",
    cache: "no-store",
    signal: AbortSignal.timeout(30_000),
    redirect: "error",
  });
  const payload = await response.json().catch(() => null);
  if (!response.ok) {
    const error = new Error("checkout_request_failed");
    error.status = response.status;
    error.code = typeof payload?.code === "string" ? payload.code : "checkout_request_failed";
    throw error;
  }
  return payload;
}

export function checkoutRedirect(value, window, token) {
  const url = new URL(value);
  const expected = new URL("../checkout-result/", window.location.href);
  const fragment = new URLSearchParams(url.hash.slice(1));
  if (url.origin !== expected.origin || url.pathname !== expected.pathname ||
      url.username || url.password || url.search || fragment.size !== 1 || fragment.get("token") !== token) {
    throw new Error("invalid_checkout_redirect");
  }
  return url;
}

export function checkoutFailureMessage(failure) {
  switch (failure?.code) {
    case "checkout_expired":
    case "checkout_not_pending":
      return "사용할 수 없는 주문 링크예요. SIDEY 상점에서 결제 상태를 확인하고 결제창을 다시 열어주세요.";
    case "commerce_not_configured":
    case "commerce_sales_disabled":
      return "지금은 결제를 이용할 수 없어요. 잠시 후 SIDEY 상점에서 다시 시도해 주세요.";
    case "commerce_rate_limited":
      return "요청이 많아요. 잠시 기다린 뒤 다시 시도해 주세요.";
    case "commerce_policy_version_mismatch":
      return "구매 조건이 변경되었어요. SIDEY 상점에서 결제창을 다시 열고 내용을 확인해 주세요.";
    default:
      return "서버에서 결제 상태를 확인할 수 없어요. 다시 결제하기 전에 SIDEY 상점에서 구매 내역을 확인해 주세요.";
  }
}
