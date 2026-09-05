(() => {
  "use strict";

  const productionHost = "whtejsviizgejauasqqt.supabase.co";
  const products = {
    character_starlight_upalupa: { image: "./assets/characters/pixel_starlight_upalupa.png", kind: "character" },
    character_guinea_pig: { image: "./assets/characters/pixel_guinea_pig.png", kind: "character" },
    character_monkey: { image: "./assets/characters/pixel_monkey.png", kind: "character" },
    character_chinchilla: { image: "./assets/characters/pixel_chinchilla.png", kind: "character" },
    bubble_bunny_pink: { image: "./assets/cosmetics/bubble_bunny_pink.png", kind: "bubble" },
    bubble_butter_chick: { image: "./assets/cosmetics/bubble_butter_chick.png", kind: "bubble" },
    bubble_starry_cat: { image: "./assets/cosmetics/bubble_starry_cat.png", kind: "bubble" },
    throwable_bouncy_heart: { image: "./assets/cosmetics/throwable_bouncy_heart.png", kind: "throwable" },
    throwable_toy_cannon: { image: "./assets/cosmetics/throwable_toy_cannon.png", kind: "effect" },
    throwable_squeaky_duck: { image: "./assets/cosmetics/throwable_squeaky_duck.png", kind: "throwable" },
  };
  const loading = document.querySelector("#checkout-loading");
  const error = document.querySelector("#checkout-error");
  const errorMessage = document.querySelector("#checkout-error-message");
  const product = document.querySelector("#checkout-product");
  const productImage = document.querySelector("#checkout-product-image");
  const previewFrame = document.querySelector("#checkout-preview-frame");
  const orderName = document.querySelector("#checkout-order-name");
  const amount = document.querySelector("#checkout-amount");
  const meta = document.querySelector("#checkout-meta");
  const consent = document.querySelector("#checkout-consent");
  const policyNotice = document.querySelector("#checkout-policy-notice");
  const payButton = document.querySelector("#checkout-pay");
  const status = document.querySelector("#checkout-status");
  let token = "";
  let apiBase = "";
  let prepared = null;

  function showError(message) {
    loading.hidden = true;
    product.hidden = true;
    errorMessage.textContent = message;
    error.hidden = false;
  }

  function validAPIBase(value) {
    try {
      const url = new URL(value);
      const loopback = url.protocol === "http:"
        && ["localhost", "127.0.0.1", "[::1]"].includes(url.hostname);
      const staging = url.protocol === "https:"
        && url.hostname.endsWith(".supabase.co")
        && url.hostname !== productionHost;
      return (loopback || staging) && url.pathname === "/functions/v1" ? url.toString().replace(/\/$/, "") : "";
    } catch {
      return "";
    }
  }

  async function request(path, body) {
    const response = await fetch(`${apiBase}/${path}`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
      cache: "no-store",
    });
    const payload = await response.json().catch(() => null);
    if (!response.ok) {
      const requestError = new Error(payload?.error || "checkout_request_failed");
      requestError.status = response.status;
      throw requestError;
    }
    return payload;
  }

  function validPrepared(config) {
    return config
      && products[config.product_id]
      && typeof config.order_name === "string"
      && Number.isSafeInteger(config.amount)
      && config.amount > 0
      && config.currency === "KRW"
      && typeof config.policy_version === "string"
      && typeof config.policy_notice === "string"
      && ["test", "live"].includes(config.payment_environment);
  }

  function validAuthorized(config) {
    try {
      const redirect = new URL(config.redirect_url);
      return validPrepared(config)
        && typeof config.store_id === "string"
        && typeof config.channel_key === "string"
        && typeof config.payment_id === "string"
        && config.pay_method === "EASY_PAY"
        && config.portone_currency === "CURRENCY_KRW"
        && redirect.origin === window.location.origin
        && redirect.pathname.endsWith("/checkout-result.html");
    } catch {
      return false;
    }
  }

  async function completePayment(config, paymentID) {
    const completion = await request("commerce-complete", { token, payment_id: paymentID });
    const resultURL = new URL(completion.result_url);
    if (resultURL.origin !== window.location.origin || !resultURL.pathname.endsWith("/checkout-result.html")) {
      throw new Error("invalid_result_url");
    }
    window.location.assign(resultURL.toString());
  }

  async function start() {
    const query = new URLSearchParams(window.location.search);
    token = new URLSearchParams(window.location.hash.slice(1)).get("token") ?? "";
    apiBase = validAPIBase(query.get("api") ?? "");
    window.history.replaceState(null, "", window.location.pathname);
    if (!/^[A-Za-z0-9_-]{43}$/.test(token) || !apiBase) {
      showError("Sidey-dev에서 새 주문을 만들어 접근해 주세요. 공개 구매 링크는 지원하지 않습니다.");
      return;
    }

    try {
      prepared = await request("commerce-checkout", { token, action: "prepare" });
      if (!validPrepared(prepared)) throw new Error("invalid_checkout_config");
      orderName.textContent = prepared.order_name;
      amount.textContent = new Intl.NumberFormat("ko-KR").format(prepared.amount);
      const preview = products[prepared.product_id];
      productImage.src = preview.image;
      productImage.alt = prepared.order_name;
      previewFrame.dataset.productKind = preview.kind;
      policyNotice.textContent = prepared.policy_notice;
      meta.textContent = `부가세 포함 · 1회 구매 · PortOne ${prepared.payment_environment === "test" ? "테스트" : "실결제"}`;
      payButton.textContent = `${amount.textContent}원 동의하고 결제창 열기`;
      payButton.disabled = !consent.checked;
      loading.hidden = true;
      product.hidden = false;
    } catch (requestError) {
      console.error(requestError);
      showError(requestError.status === 410
        ? "주문 링크가 만료되었거나 이미 처리되었습니다. Sidey-dev 상점에서 다시 시도해 주세요."
        : "서버에서 주문을 확인하지 못했습니다. Sidey-dev 상점에서 다시 시도해 주세요.");
    }
  }

  payButton.addEventListener("click", async () => {
    if (!consent.checked) {
      status.textContent = "구매 조건과 환불 안내에 먼저 동의해 주세요.";
      consent.focus();
      return;
    }
    payButton.disabled = true;
    status.textContent = "PortOne 결제창을 준비하고 있어요…";
    try {
      const config = await request("commerce-checkout", {
        token,
        action: "authorize",
        policy_version: prepared.policy_version,
      });
      if (!validAuthorized(config) || typeof window.PortOne?.requestPayment !== "function") {
        throw new Error("portone_sdk_unavailable");
      }
      const response = await window.PortOne.requestPayment({
        storeId: config.store_id,
        channelKey: config.channel_key,
        paymentId: config.payment_id,
        orderName: config.order_name,
        totalAmount: config.amount,
        currency: config.portone_currency,
        payMethod: config.pay_method,
        redirectUrl: config.redirect_url,
      });
      if (response?.code !== undefined) {
        payButton.disabled = !consent.checked;
        status.textContent = response.message || "결제를 완료하지 않았습니다.";
        return;
      }
      if (response?.paymentId !== config.payment_id) throw new Error("payment_id_mismatch");
      status.textContent = "SIDEY 서버가 결제 상태를 확인하고 있어요…";
      await completePayment(config, response.paymentId);
    } catch (paymentError) {
      console.error(paymentError);
      payButton.disabled = !consent.checked;
      status.textContent = "결제 상태를 확인하지 못했습니다. 중복 결제하지 말고 상점 상태를 먼저 새로고침해 주세요.";
    }
  });

  consent.addEventListener("change", () => {
    payButton.disabled = !consent.checked || prepared === null;
  });

  start();
})();
