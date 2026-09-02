import {
  assertRuntimePaymentConfiguration,
  jsonResponse,
  serviceRPC,
  sha256Hex,
  tossRequest,
  type TossPayment,
} from "../_shared/commerce.ts";

Deno.serve(async (request) => {
  if (request.method !== "POST") return jsonResponse({ error: "method_not_allowed" }, 405);
  try {
    const rawBody = await request.text();
    const payloadHash = await sha256Hex(rawBody);
    const event = JSON.parse(rawBody);
    const eventType = typeof event?.eventType === "string" ? event.eventType : "UNKNOWN";
    const candidate = event?.data;
    if (eventType !== "PAYMENT_STATUS_CHANGED" || typeof candidate?.paymentKey !== "string") {
      return jsonResponse({ accepted: true, ignored: true });
    }

    // General payment webhooks are not signed. Never trust their Payment body;
    // query Toss directly with the merchant secret and apply that response only.
    await assertRuntimePaymentConfiguration();
    const verified = await tossRequest<TossPayment>(`/payments/${encodeURIComponent(candidate.paymentKey)}`);
    const transmissionID = request.headers.get("tosspayments-webhook-transmission-id");
    const eventID = (transmissionID && transmissionID.length <= 180)
      ? `toss:${transmissionID}`
      : `toss:${payloadHash}`;
    const status = await serviceRPC<string>("commerce_record_provider_state", {
      p_event_id: eventID,
      p_event_type: eventType,
      p_payload_sha256_hex: payloadHash,
      p_provider_order_id: verified.orderId,
      p_payment_key: verified.paymentKey,
      p_amount_krw: verified.totalAmount,
      p_balance_amount_krw: verified.balanceAmount,
      p_currency: verified.currency,
      p_provider_status: verified.status,
      p_provider_transaction_key: verified.lastTransactionKey ?? null,
      p_verified_at: new Date().toISOString(),
    });
    return jsonResponse({ accepted: true, status });
  } catch (error) {
    console.error(error);
    // Non-2xx makes Toss retry transient failures.
    return jsonResponse({ accepted: false, error: "webhook_processing_failed" }, 500);
  }
});
