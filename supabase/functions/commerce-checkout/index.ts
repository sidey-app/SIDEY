import {
  corsHeaders,
  functionURL,
  jsonResponse,
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

    const rows = await serviceRPC<CommerceOrder[]>("commerce_checkout_order", {
      p_checkout_token_hash_hex: await sha256Hex(token),
    });
    const order = rows[0];
    if (!order) return jsonResponse({ error: "checkout_expired" }, 410);

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
    });
  } catch (error) {
    console.error(error);
    return jsonResponse({ error: "checkout_unavailable" }, 500);
  }
});
