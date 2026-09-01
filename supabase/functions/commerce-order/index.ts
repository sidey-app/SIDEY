import {
  assertCheckoutConfiguration,
  authenticatedUser,
  checkoutPageURL,
  corsHeaders,
  jsonResponse,
  PRODUCT_ID,
  publicError,
  randomToken,
  sha256Hex,
  userRPC,
  type CommerceOrder,
} from "../_shared/commerce.ts";

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return jsonResponse({ error: "method_not_allowed" }, 405);

  try {
    const authorization = request.headers.get("authorization");
    await authenticatedUser(authorization);
    assertCheckoutConfiguration();
    const payload = await request.json().catch(() => ({}));
    if (payload?.product_id !== PRODUCT_ID) {
      return jsonResponse({ error: "commerce_product_unavailable" }, 400);
    }

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
