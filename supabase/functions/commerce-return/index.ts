import {
  assertRuntimePaymentConfiguration,
  checkoutResultURL,
  redirectResponse,
  serviceRPC,
  sha256Hex,
  tossRequest,
  validatePayment,
  type CommerceOrder,
  type TossPayment,
} from "../_shared/commerce.ts";

function resultRedirect(result: string): Response {
  return redirectResponse(checkoutResultURL(result));
}

Deno.serve(async (request) => {
  if (request.method !== "GET") return resultRedirect("invalid");
  const url = new URL(request.url);
  const token = url.searchParams.get("token") ?? "";

  if (url.searchParams.get("result") !== "success") {
    if (/^[A-Za-z0-9_-]{43}$/.test(token)) {
      await serviceRPC<boolean>("commerce_cancel_checkout", {
        p_checkout_token_hash_hex: await sha256Hex(token),
      }).catch((error) => console.error("Unable to cancel checkout", error));
    }
    return resultRedirect("canceled");
  }

  try {
    const paymentKey = url.searchParams.get("paymentKey") ?? "";
    const providerOrderID = url.searchParams.get("orderId") ?? "";
    const amount = Number(url.searchParams.get("amount"));
    if (!/^[A-Za-z0-9_-]{43}$/.test(token) || !Number.isSafeInteger(amount) || !paymentKey) {
      return resultRedirect("invalid");
    }
    const rows = await serviceRPC<CommerceOrder[]>("commerce_checkout_order", {
      p_checkout_token_hash_hex: await sha256Hex(token),
    });
    const order = rows[0];
    if (!order || providerOrderID !== order.provider_order_id || amount !== order.amount_krw) {
      return resultRedirect("mismatch");
    }
    await assertRuntimePaymentConfiguration();

    validatePayment(await tossRequest<TossPayment>("/payments/confirm", {
      method: "POST",
      idempotencyKey: `confirm-${order.order_id}`,
      body: { paymentKey, orderId: order.provider_order_id, amount: order.amount_krw },
    }), order);
    const verified = validatePayment(await tossRequest<TossPayment>(
      `/payments/${encodeURIComponent(paymentKey)}`,
    ), order);
    if (verified.status !== "DONE") return resultRedirect("pending");

    await serviceRPC<string>("commerce_record_approval", {
      p_provider_order_id: verified.orderId,
      p_payment_key: verified.paymentKey,
      p_amount_krw: verified.totalAmount,
      p_currency: verified.currency,
      p_provider_transaction_key: verified.lastTransactionKey ?? null,
      p_verified_at: new Date().toISOString(),
    });
    return resultRedirect("success");
  } catch (error) {
    console.error(error);
    return resultRedirect("error");
  }
});
