import {
  assertCheckoutConfiguration,
  authenticatedUser,
  checkoutPageURL,
  corsHeaders,
  HttpError,
  jsonResponse,
  PRODUCT_ID,
  publicError,
  randomToken,
  serviceRPC,
  sha256Hex,
  userRPC,
  type CommerceOrder,
  type CommerceRuntimeConfiguration,
} from "../_shared/commerce.ts";

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return jsonResponse({ error: "method_not_allowed" }, 405);

  try {
    const authorization = request.headers.get("authorization");
    await authenticatedUser(authorization);
    const payload = await request.json().catch(() => ({}));
    if (payload?.product_id !== PRODUCT_ID) {
      return jsonResponse({ error: "commerce_product_unavailable" }, 400);
    }

    const runtimeRows = await serviceRPC<CommerceRuntimeConfiguration[]>(
      "commerce_runtime_configuration",
      {},
    );
    const runtime = runtimeRows[0];
    if (!runtime?.sales_enabled) {
      throw new HttpError(503, "commerce_sales_disabled", "현재 판매 준비 중입니다.");
    }
    assertCheckoutConfiguration(runtime.payment_environment);

    const checkoutToken = randomToken();
    const tokenHash = await sha256Hex(checkoutToken);
    const rows = await userRPC<CommerceOrder[]>(
      "create_commerce_order",
      { p_product_id: PRODUCT_ID, p_checkout_token_hash_hex: tokenHash },
      authorization!,
    );
    const order = rows[0];
    if (!order) throw new Error("commerce_order_missing");

    return jsonResponse({
      order_id: order.order_id,
      checkout_url: checkoutPageURL(checkoutToken),
    }, 201);
  } catch (error) {
    return publicError(error);
  }
});
