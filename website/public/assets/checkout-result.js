import { checkoutContext, commerceRequest } from "./checkout-api.js";

export async function mountCheckoutResult(document, window) {
  function render(state) {
    const results = {
      success: ["✓", "결제가 완료되었어요.", "구매한 상품의 사용권이 계정에 추가되었어요. SIDEY 상점에서 확인해 주세요."],
      refunded: ["!", "환불된 결제입니다.", "현재 상품 사용권은 SIDEY 상점에서 확인해 주세요."],
      canceled: ["!", "결제가 완료되지 않았어요.", "SIDEY 상점에서 결제 상태를 확인한 뒤 다시 시도해 주세요."],
      error: ["!", "결제 상태를 확인할 수 없어요.", "SIDEY 상점에서 결제 상태를 확인해 주세요. 결제를 다시 시도하기 전에 구매 내역을 확인해 주세요."],
      invalid: ["!", "결제 결과를 확인할 수 없어요.", "이 창을 닫고 SIDEY 상점에서 구매 내역을 확인해 주세요."],
    };
    const [icon, title, message] = results[state];
    document.querySelector("#result-icon").textContent = icon;
    document.querySelector("#result-title").textContent = title;
    document.querySelector("#result-message").textContent = message;
    document.title = title + " · SIDEY";
  }

  let context;
  try {
    context = checkoutContext(document, window);
  } catch {
    render("invalid");
    return;
  }
  const paymentId = context.query.get("paymentId");
  if (!paymentId || paymentId.length < 6 || paymentId.length > 200) {
    render("invalid");
    return;
  }
  try {
    const response = await commerceRequest(window, context.apiBase, "complete", { token: context.token, paymentId });
    const state = response?.completed === true && response.status === "approved" ? "success"
      : response?.completed === false && response.status === "refunded" ? "refunded" : "error";
    render(state);
  } catch (failure) {
    render(failure.code === "payment_not_paid" && context.query.has("code") ? "canceled" : "error");
  }
}

if (typeof document !== "undefined") mountCheckoutResult(document, window);
