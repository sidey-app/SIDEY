import { commerceProducts } from "./commerce-products.js";
import { checkoutContext, checkoutRedirect, commerceRequest, checkoutFailureMessage } from "./checkout-api.js";

function validOrder(order) {
  return order && Object.hasOwn(commerceProducts, order.productId) &&
    [order.orderId, order.orderName, order.policyVersion, order.policyNotice].every(value => typeof value === "string" && value.length > 0) &&
    Number.isSafeInteger(order.amount) && order.amount > 0 && order.currency === "KRW" &&
    typeof order.requiresConsent === "boolean";
}

export function mountCheckout(document, window) {
  const element = name => document.querySelector("#checkout-" + name);
  const loading = element("loading"), error = element("error"), product = element("product");
  const consent = element("consent"), pay = element("pay"), status = element("status");
  let context, prepared, working = false;
  const showError = message => {
    loading.hidden = true;
    product.hidden = true;
    error.hidden = false;
    element("error-message").textContent = message;
  };
  const updateButton = () => { pay.disabled = working || !prepared || !consent.checked; };

  consent.addEventListener("change", updateButton);
  pay.addEventListener("click", async () => {
    if (working || !prepared) return;
    if (!consent.checked) {
      status.textContent = "구매 조건과 환불 안내에 동의해 주세요.";
      consent.focus();
      return;
    }
    working = true;
    updateButton();
    status.textContent = "결제창을 열고 있어요.";
    try {
      const config = await commerceRequest(window, context.apiBase, "checkout", {
        token: context.token, action: "authorize", policyVersion: prepared.policyVersion,
      });
      if (!validOrder(config) || config.orderId !== prepared.orderId || config.productId !== prepared.productId ||
          config.amount !== prepared.amount || config.policyVersion !== prepared.policyVersion ||
          config.policyNotice !== prepared.policyNotice || config.requiresConsent !== false ||
          ![config.storeId, config.channelKey].every(value => typeof value === "string" && value.length > 0) ||
          typeof config.paymentId !== "string" || config.paymentId.length < 6 || config.paymentId.length > 200 ||
          config.payMethod !== "EASY_PAY" || config.portoneCurrency !== "CURRENCY_KRW" ||
          typeof window.PortOne?.requestPayment !== "function") throw new Error("invalid_checkout_authorization");
      const redirect = checkoutRedirect(config.redirectUrl, window, context.token);
      const response = await window.PortOne.requestPayment({
        storeId: config.storeId, channelKey: config.channelKey, paymentId: config.paymentId,
        orderName: config.orderName, totalAmount: config.amount, currency: config.portoneCurrency,
        payMethod: config.payMethod, redirectUrl: redirect.href,
      });
      if (response?.code !== undefined) {
        status.textContent = "결제창을 닫았습니다. SIDEY 상점에서 결제 상태를 확인해 주세요.";
        return;
      }
      if (response?.paymentId !== config.paymentId) throw new Error("invalid_payment_response");
      redirect.searchParams.set("paymentId", config.paymentId);
      window.location.assign(redirect.href);
    } catch (failure) {
      status.textContent = checkoutFailureMessage(failure);
    } finally {
      working = false;
      updateButton();
    }
  });

  async function start() {
    try {
      context = checkoutContext(document, window);
    } catch {
      showError("결제 링크를 확인할 수 없어요. SIDEY 상점에서 결제창을 다시 열어주세요.");
      return;
    }
    try {
      const order = await commerceRequest(window, context.apiBase, "checkout", { token: context.token, action: "prepare" });
      if (!validOrder(order)) throw new Error("invalid_checkout_order");
      prepared = order;
      const item = commerceProducts[order.productId];
      element("order-name").textContent = order.orderName;
      element("amount").textContent = order.amount.toLocaleString("ko-KR");
      element("meta").textContent = "부가세 포함 · 1회 구매";
      element("policy-notice").textContent = order.policyNotice;
      element("product-image").src = new URL("../" + item.image, import.meta.url).href;
      element("product-image").alt = item.name;
      element("preview-frame").dataset.productKind = item.kind;
      loading.hidden = true;
      product.hidden = false;
      updateButton();
    } catch (failure) {
      prepared = null;
      showError(checkoutFailureMessage(failure));
    }
  }
  return { ready: start() };
}

if (typeof document !== "undefined") mountCheckout(document, window);
