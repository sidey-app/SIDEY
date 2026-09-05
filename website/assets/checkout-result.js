(() => {
  "use strict";

  const productionHost = "whtejsviizgejauasqqt.supabase.co";
  const productNames = {
    character_starlight_upalupa: "별빛 우파루파",
    character_guinea_pig: "아기 기니피그",
    character_monkey: "아기 원숭이",
    character_chinchilla: "아기 친칠라",
    bubble_bunny_pink: "핑크 토끼 말풍선",
    bubble_butter_chick: "버터 병아리 말풍선",
    bubble_starry_cat: "별밤 고양이 말풍선",
    throwable_bouncy_heart: "통통 하트",
    throwable_toy_cannon: "미니 대포",
    throwable_squeaky_duck: "삑삑 오리",
  };
  const results = {
    success: (name) => ({
      icon: "✦",
      title: `${name} 사용권이 도착했어요.`,
      message: "PortOne 결제 재조회와 디지털 꾸미기 사용권 지급이 끝났습니다. SIDEY 상점에서 보유 상태를 확인해 주세요.",
    }),
    canceled: () => ({
      icon: "!", title: "결제를 완료하지 않았어요.",
      message: "SIDEY 상점에서 다시 시도할 수 있습니다.",
    }),
    error: () => ({
      icon: "!", title: "결제를 확인하는 중 문제가 생겼어요.",
      message: "중복 결제하지 말고 SIDEY 상점에서 보유 상태를 먼저 새로고침해 주세요.",
    }),
    invalid: () => ({
      icon: "!", title: "결제 정보를 확인할 수 없어요.",
      message: "SIDEY 앱 상점에서 새 주문을 만들어 다시 시도해 주세요.",
    }),
  };

  const icon = document.querySelector("#result-icon");
  const title = document.querySelector("#result-title");
  const message = document.querySelector("#result-message");

  function render(key, productID) {
    const name = productNames[productID] || "SIDEY 디지털 꾸미기";
    const result = (results[key] || results.invalid)(name);
    icon.textContent = result.icon;
    title.textContent = result.title;
    message.textContent = result.message;
    document.title = `${result.title} · SIDEY`;
  }

  function validAPIBase(value) {
    try {
      const url = new URL(value);
      const loopback = url.protocol === "http:"
        && ["localhost", "127.0.0.1", "[::1]"].includes(url.hostname);
      const staging = url.protocol === "https:"
        && url.hostname.endsWith(".supabase.co")
        && url.hostname !== productionHost;
      return (loopback || staging) && url.pathname === "/functions/v1"
        ? url.toString().replace(/\/$/, "")
        : "";
    } catch {
      return "";
    }
  }

  async function completeRedirect(query, productID) {
    const token = new URLSearchParams(window.location.hash.slice(1)).get("token") ?? "";
    const paymentID = query.get("paymentId") ?? "";
    const apiBase = validAPIBase(query.get("api") ?? "");
    window.history.replaceState(null, "", window.location.pathname);
    if (!apiBase || !/^[A-Za-z0-9_-]{43}$/.test(token) || paymentID.length < 6 || query.get("code")) {
      render(query.get("code") ? "canceled" : "invalid", productID);
      return;
    }
    try {
      const response = await fetch(`${apiBase}/commerce-complete`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ token, payment_id: paymentID }),
        cache: "no-store",
      });
      const payload = await response.json().catch(() => null);
      if (!response.ok || payload?.completed !== true) throw new Error(payload?.error || "complete_failed");
      const resultURL = new URL(payload.result_url);
      if (resultURL.origin !== window.location.origin || !resultURL.pathname.endsWith("/checkout-result.html")) {
        throw new Error("invalid_result_url");
      }
      window.location.replace(resultURL.toString());
    } catch (completionError) {
      console.error(completionError);
      render("error", productID);
    }
  }

  const query = new URLSearchParams(window.location.search);
  const productID = query.get("product") ?? "";
  const result = query.get("result") ?? "invalid";
  if (result === "complete") {
    completeRedirect(query, productID);
  } else {
    render(result, productID);
  }
})();
