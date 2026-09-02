import {
  assertCheckoutConfiguration,
  corsHeaders,
  functionURL,
  HttpError,
  jsonResponse,
  publicError,
  serviceRPC,
  sha256Hex,
  tossClientKey,
  type CommerceOrder,
} from "../_shared/commerce.ts";

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return jsonResponse({ error: "method_not_allowed" }, 405);

  try {
    const payload = await request.json().catch(() => ({}));
    const token = typeof payload?.token === "string" ? payload.token : "";
    if (!/^[A-Za-z0-9_-]{43}$/.test(token)) {
      return jsonResponse({ error: "invalid_checkout_token" }, 400);
    }

    const action = payload?.action === "consent" ? "consent" : "prepare";
    if (action === "consent" && payload?.accepted !== true) {
      throw new HttpError(400, "payment_policy_consent_required", "결제 조건 동의가 필요합니다.");
    }
    const tokenHash = await sha256Hex(token);
    const rows = action === "consent"
      ? await serviceRPC<CommerceOrder[]>("commerce_record_policy_consent", {
        p_checkout_token_hash_hex: tokenHash,
        p_policy_version: typeof payload?.policy_version === "string"
          ? payload.policy_version
          : "",
      })
      : await serviceRPC<CommerceOrder[]>("commerce_checkout_prepare", {
        p_checkout_token_hash_hex: tokenHash,
      });
    const order = rows[0];
    if (!order) return jsonResponse({ error: "checkout_expired" }, 410);
    if (
      typeof order.policy_version !== "string"
      || typeof order.policy_notice !== "string"
      || (order.payment_environment !== "test" && order.payment_environment !== "live")
    ) {
      throw new HttpError(503, "commerce_not_configured");
    }
    assertCheckoutConfiguration(order.payment_environment);

    if (action === "prepare") {
      return jsonResponse({
        order_name: order.display_name,
        amount: order.amount_krw,
        currency: order.currency,
        policy_version: order.policy_version,
        policy_notice: order.policy_notice,
        consent_recorded: Boolean(order.policy_consented_at),
        payment_environment: order.payment_environment,
      });
    }

    if (payload?.accepted !== true || !order.policy_consented_at) {
      throw new HttpError(400, "payment_policy_consent_required", "결제 조건 동의가 필요합니다.");
    }

    const returnURL = functionURL("commerce-return");
    const successURL = new URL(returnURL);
    successURL.searchParams.set("result", "success");
    successURL.searchParams.set("token", token);
    const failURL = new URL(returnURL);
    failURL.searchParams.set("result", "fail");
    failURL.searchParams.set("token", token);

    return jsonResponse({
      client_key: tossClientKey(),
      customer_key: order.provider_order_id,
      order_id: order.provider_order_id,
      order_name: order.display_name,
      amount: order.amount_krw,
      currency: order.currency,
      customer_name: order.customer_name ?? "SIDEY 사용자",
      success_url: successURL.toString(),
      fail_url: failURL.toString(),
      policy_version: order.policy_version,
      consent_recorded: true,
      payment_environment: order.payment_environment,
    });
  } catch (error) {
    return publicError(error);
  }
});
