(() => {
  "use strict";

  const results = {
    success: {
      icon: "✦",
      title: "별빛 우파루파가 도착했어요.",
      message: "서버 결제 확인과 캐릭터 소유권 지급이 끝났습니다. SIDEY 상점에서 보유 상태를 확인해주세요.",
    },
    canceled: {
      icon: "!",
      title: "결제를 완료하지 않았어요.",
      message: "승인되거나 청구된 금액은 없습니다. SIDEY 상점에서 다시 시도할 수 있어요.",
    },
    pending: {
      icon: "…",
      title: "결제 승인을 확인하고 있어요.",
      message: "중복 결제하지 말고 SIDEY 상점에서 보유 상태를 먼저 새로고침해주세요.",
    },
    mismatch: {
      icon: "!",
      title: "결제 정보가 주문과 일치하지 않아요.",
      message: "결제를 승인하지 않았습니다. SIDEY 지원팀에 문의해주세요.",
    },
    invalid: {
      icon: "!",
      title: "결제 정보를 확인할 수 없어요.",
      message: "주문 정보가 빠졌거나 올바르지 않습니다. SIDEY 상점에서 다시 시도해주세요.",
    },
    error: {
      icon: "!",
      title: "결제를 확인하는 중 문제가 생겼어요.",
      message: "중복 결제하지 말고 SIDEY 상점에서 보유 상태를 먼저 새로고침해주세요.",
    },
  };

  const key = new URLSearchParams(window.location.search).get("result") ?? "invalid";
  const result = results[key] ?? results.invalid;
  document.querySelector("#result-icon").textContent = result.icon;
  document.querySelector("#result-title").textContent = result.title;
  document.querySelector("#result-message").textContent = result.message;
  document.title = `${result.title} · SIDEY`;
})();
