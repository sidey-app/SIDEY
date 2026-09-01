(() => {
  "use strict";

  const shell = document.querySelector(".checkout-shell");
  const loading = document.querySelector("#checkout-loading");
  const error = document.querySelector("#checkout-error");
  const errorMessage = document.querySelector("#checkout-error-message");
  const product = document.querySelector("#checkout-product");
  const orderName = document.querySelector("#checkout-order-name");
  const amount = document.querySelector("#checkout-amount");
  const payButton = document.querySelector("#checkout-pay");
  const status = document.querySelector("#checkout-status");
  const checkoutEndpoint = shell?.dataset.checkoutEndpoint ?? "";
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

  function validCheckoutConfig(config) {
    return config
      && typeof config.client_key === "string"
      && config.client_key.length > 0
      && typeof config.customer_key === "string"
      && config.customer_key.length >= 6
      && typeof config.order_id === "string"
      && config.order_id.length >= 6
      && typeof config.order_name === "string"
      && config.order_name.length > 0
      && Number.isSafeInteger(config.amount)
      && config.amount > 0
      && config.currency === "KRW"
      && typeof config.customer_name === "string"
      && validReturnURL(config.success_url)
      && validReturnURL(config.fail_url);
  }

  async function loadCheckout() {
    const token = new URLSearchParams(window.location.hash.slice(1)).get("token") ?? "";
    window.history.replaceState(null, "", `${window.location.pathname}${window.location.search}`);
    if (!/^[A-Za-z0-9_-]{43}$/.test(token) || !checkoutEndpoint) {
      showError("주문 링크가 올바르지 않습니다. SIDEY 상점에서 새 주문을 만들어주세요.");
      return;
    }

    try {
      const response = await fetch(checkoutEndpoint, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ token }),
        cache: "no-store",
      });
      const config = await response.json().catch(() => null);
      if (response.status === 410) {
        showError("주문 링크가 만료되었거나 이미 처리되었습니다. SIDEY 상점에서 다시 시도해주세요.");
        return;
      }
      if (!response.ok || !validCheckoutConfig(config)) {
        showError("서버에서 주문을 확인하지 못했습니다. SIDEY 상점에서 다시 시도해주세요.");
        return;
      }

      orderName.textContent = config.order_name;
      amount.textContent = new Intl.NumberFormat("ko-KR").format(config.amount);
      payButton.textContent = `${amount.textContent}원 결제창 열기`;
      loading.hidden = true;
      product.hidden = false;

      payButton.addEventListener("click", async () => {
        payButton.disabled = true;
        status.textContent = "결제창을 준비하고 있어요…";
        try {
          if (typeof window.TossPayments !== "function") throw new Error("toss_sdk_unavailable");
          const tossPayments = window.TossPayments(config.client_key);
          const widgets = tossPayments.widgets({ customerKey: config.customer_key });
          await widgets.setAmount({ currency: config.currency, value: config.amount });
          paymentWindow = await widgets.renderPaymentWindow();
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
              payButton.disabled = false;
              status.textContent = "결제 요청을 완료하지 못했습니다. 다시 시도해주세요.";
            }
          });
          paymentWindow.on("cancel", () => {
            payButton.disabled = false;
            status.textContent = "결제창을 닫았습니다. 다시 시도할 수 있어요.";
          });
        } catch (paymentError) {
          console.error(paymentError);
          payButton.disabled = false;
          status.textContent = "결제창을 열지 못했습니다. 잠시 뒤 다시 시도해주세요.";
        }
      });
    } catch (requestError) {
      console.error(requestError);
      showError("결제 서버에 연결하지 못했습니다. 네트워크를 확인하고 다시 시도해주세요.");
    }
  }

  loadCheckout();
})();
