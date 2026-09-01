import {
  constantTimeEqual,
  HttpError,
  jsonResponse,
  publicError,
  serviceRPC,
  sha256Hex,
  tossRequest,
  type CommerceOrder,
  type TossPayment,
} from "../_shared/commerce.ts";

type RefundTarget = Pick<CommerceOrder, "provider_order_id" | "amount_krw" | "currency"> & {
  payment_key: string;
};

Deno.serve(async (request) => {
  if (request.method !== "POST") return jsonResponse({ error: "method_not_allowed" }, 405);
  try {
    const configuredKey = Deno.env.get("SIDEY_COMMERCE_OPS_KEY") ?? "";
    const suppliedKey = request.headers.get("x-sidey-commerce-ops-key") ?? "";
    if (!configuredKey || !suppliedKey || !(await constantTimeEqual(configuredKey, suppliedKey))) {
      throw new HttpError(401, "operations_authentication_required", "운영 인증이 필요합니다.");
    }
    const payload = await request.json().catch(() => ({}));
    if (typeof payload?.order_id !== "string") throw new HttpError(400, "invalid_order_id");
    const targets = await serviceRPC<RefundTarget[]>("commerce_refund_target", {
      p_order_id: payload.order_id,
    });
    const target = targets[0];
    if (!target) {
      throw new HttpError(409, "refund_not_available", "승인 후 7일이 지난 주문이거나 환불할 수 없는 상태입니다.");
    }

    const canceled = await tossRequest<TossPayment>(
      `/payments/${encodeURIComponent(target.payment_key)}/cancel`,
      {
        method: "POST",
        idempotencyKey: `refund-${payload.order_id}`,
        body: { cancelReason: "SIDEY 7일 이내 전액 환불" },
      },
    );
    if (canceled.orderId !== target.provider_order_id || canceled.totalAmount !== target.amount_krw) {
      throw new HttpError(409, "refund_verification_failed");
    }
    const payment = await tossRequest<TossPayment>(
      `/payments/${encodeURIComponent(target.payment_key)}`,
    );
    if (
      payment.orderId !== target.provider_order_id
      || payment.paymentKey !== target.payment_key
      || payment.totalAmount !== target.amount_krw
      || payment.currency !== target.currency
    ) {
      throw new HttpError(409, "refund_verification_failed");
    }
    const verificationHash = await sha256Hex([
      payment.paymentKey,
      payment.orderId,
      payment.status,
      payment.totalAmount,
      payment.balanceAmount,
      payment.currency,
      payment.lastTransactionKey ?? "",
    ].join("\n"));
    const status = await serviceRPC<string>("commerce_record_provider_state", {
      p_event_id: `refund:${payload.order_id}`,
      p_event_type: "SIDEY_REFUND",
      p_payload_sha256_hex: verificationHash,
      p_provider_order_id: payment.orderId,
      p_payment_key: payment.paymentKey,
      p_amount_krw: payment.totalAmount,
      p_balance_amount_krw: payment.balanceAmount,
      p_currency: payment.currency,
      p_provider_status: payment.status,
      p_provider_transaction_key: payment.lastTransactionKey ?? null,
      p_verified_at: new Date().toISOString(),
    });
    return jsonResponse({ refunded: status === "refunded", status });
  } catch (error) {
    return publicError(error);
  }
});
