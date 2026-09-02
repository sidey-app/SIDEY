(() => {
  "use strict";

  const shell = document.querySelector(".checkout-shell");
  const loading = document.querySelector("#checkout-loading");
  const error = document.querySelector("#checkout-error");
  const errorMessage = document.querySelector("#checkout-error-message");
  const product = document.querySelector("#checkout-product");
  const orderName = document.querySelector("#checkout-order-name");
  const amount = document.querySelector("#checkout-amount");
  const environment = document.querySelector("#checkout-environment");
  const policyNotice = document.querySelector("#checkout-policy-notice");
  const consent = document.querySelector("#checkout-consent");
  const payButton = document.querySelector("#checkout-pay");
  const status = document.querySelector("#checkout-status");
  const checkoutEndpoint = shell?.dataset.checkoutEndpoint ?? "";
  let checkoutToken = "";
  let preparedOrder = null;
  let paymentWindow = null;

  function showError(message) {
    loading.hidden = true;
    product.hidden = true;
    errorMessage.textContent = message;
    error.hidden = false;
  }

  function validReturnURL(value) {
    try {
      const url = new URL(value);
      return url.protocol === "https:"
        && url.hostname === "whtejsviizgejauasqqt.supabase.co"
        && url.pathname === "/functions/v1/commerce-return";
    } catch {
      return false;
    }
  }

  function validPreparedOrder(config) {
    return config
      && typeof config.order_name === "string"
      && config.order_name.length > 0
      && Number.isSafeInteger(config.amount)
      && config.amount > 0
      && config.currency === "KRW"
      && typeof config.policy_version === "string"
      && config.policy_version.length > 0
      && typeof config.policy_notice === "string"
      && config.policy_notice.length >= 80
      && ["test", "live"].includes(config.payment_environment);
  }

  function validPaymentConfig(config) {
    return config
      && preparedOrder
      && config.policy_version === preparedOrder.policy_version
      && config.payment_environment === preparedOrder.payment_environment
      && config.consent_recorded === true
      && config.order_name === preparedOrder.order_name
      && config.amount === preparedOrder.amount
      && config.currency === preparedOrder.currency
      && typeof config.client_key === "string"
      && config.client_key.length > 0
      && typeof config.customer_key === "string"
      && config.customer_key.length >= 6
      && typeof config.order_id === "string"
      && config.order_id.length >= 6
      && typeof config.customer_name === "string"
      && validReturnURL(config.success_url)
      && validReturnURL(config.fail_url);
  }

  async function requestCheckout(body) {
    const response = await fetch(checkoutEndpoint, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
      cache: "no-store",
    });
    const payload = await response.json().catch(() => null);
    if (response.status === 410) throw new Error("checkout_expired");
    if (!response.ok) {
      throw new Error(typeof payload?.error === "string" ? payload.error : "checkout_unavailable");
    }
    return payload;
  }

  function setControlsEnabled(enabled) {
    consent.disabled = !enabled;
    payButton.disabled = !enabled || !consent.checked;
  }

  async function openPaymentWindow() {
    if (!consent.checked) {
      payButton.disabled = true;
      status.textContent = "결제 조건을 확인하고 동의해 주세요.";
      return;
    }
    setControlsEnabled(false);
    status.textContent = "동의 내용을 안전하게 기록하고 있어요…";
    try {
      const config = await requestCheckout({
        token: checkoutToken,
        action: "consent",
        accepted: true,
        policy_version: preparedOrder.policy_version,
      });
      if (!validPaymentConfig(config)) throw new Error("invalid_checkout_config");

      status.textContent = "결제창을 준비하고 있어요…";
      if (typeof window.TossPayments !== "function") throw new Error("toss_sdk_unavailable");
      const tossPayments = window.TossPayments(config.client_key);
      const widgets = tossPayments.widgets({ customerKey: config.customer_key });
      await widgets.setAmount({ currency: config.currency, value: config.amount });
      paymentWindow = await widgets.renderPaymentWindow({
        variantKey: { paymentMethod: "sideyCheckout" },
      });
      paymentWindow.on("paymentRequest", async () => {
        status.textContent = "결제 인증을 진행하고 있어요…";
        try {
          await widgets.requestPayment({
            orderId: config.order_id,
            orderName: config.order_name,
            customerName: config.customer_name,
            successUrl: config.success_url,
            failUrl: config.fail_url,
            windowTarget: "self",
          });
        } catch (requestError) {
          console.error(requestError);
          setControlsEnabled(true);
          status.textContent = "결제 요청을 완료하지 못했습니다. 다시 시도해주세요.";
        }
      });
      paymentWindow.on("cancel", () => {
        setControlsEnabled(true);
        status.textContent = "결제창을 닫았습니다. 다시 시도할 수 있어요.";
      });
    } catch (paymentError) {
      console.error(paymentError);
      setControlsEnabled(true);
      status.textContent = paymentError.message === "checkout_expired"
        ? "주문 링크가 만료되었습니다. SIDEY 상점에서 다시 시작해주세요."
        : "동의를 기록하거나 결제창을 열지 못했습니다. 잠시 뒤 다시 시도해주세요.";
    }
  }

  async function loadCheckout() {
    checkoutToken = new URLSearchParams(window.location.hash.slice(1)).get("token") ?? "";
    window.history.replaceState(null, "", `${window.location.pathname}${window.location.search}`);
    if (!/^[A-Za-z0-9_-]{43}$/.test(checkoutToken) || !checkoutEndpoint) {
      showError("주문 링크가 올바르지 않습니다. SIDEY 상점에서 새 주문을 만들어주세요.");
      return;
    }

    try {
      preparedOrder = await requestCheckout({ token: checkoutToken, action: "prepare" });
      if (!validPreparedOrder(preparedOrder)) throw new Error("invalid_checkout_config");

      orderName.textContent = preparedOrder.order_name;
      amount.textContent = new Intl.NumberFormat("ko-KR").format(preparedOrder.amount);
      if (preparedOrder.payment_environment === "test") {
        environment.textContent = " · 테스트 모드 · 실제 청구 없음";
        environment.hidden = false;
      } else {
        environment.textContent = "";
        environment.hidden = true;
      }
      policyNotice.textContent = preparedOrder.policy_notice;
      payButton.textContent = `${amount.textContent}원 결제창 열기`;
      consent.checked = false;
      consent.addEventListener("change", () => {
        payButton.disabled = !consent.checked;
        status.textContent = "";
      });
      payButton.addEventListener("click", openPaymentWindow);
      setControlsEnabled(true);
      loading.hidden = true;
      product.hidden = false;
    } catch (requestError) {
      console.error(requestError);
      showError(requestError.message === "checkout_expired"
        ? "주문 링크가 만료되었거나 이미 처리되었습니다. SIDEY 상점에서 다시 시도해주세요."
        : "주문 정보를 확인하지 못했습니다. SIDEY 상점에서 다시 시도해주세요.");
    }
  }

  loadCheckout();
})();
