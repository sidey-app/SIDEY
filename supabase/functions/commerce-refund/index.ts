import {
  assertRuntimePaymentConfiguration,
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
  request_id: string;
  payment_key: string;
};

const allowedReasonCodes = new Set([
  "not_provided",
  "contract_mismatch",
  "duplicate_payment",
  "unauthorized_payment",
  "minor_without_consent",
  "other_statutory_reason",
]);

Deno.serve(async (request) => {
  if (request.method !== "POST") return jsonResponse({ error: "method_not_allowed" }, 405);
  const audit = { orderID: "", requested: false };
  try {
    const configuredKey = Deno.env.get("SIDEY_COMMERCE_OPS_KEY") ?? "";
    const suppliedKey = request.headers.get("x-sidey-commerce-ops-key") ?? "";
    if (!configuredKey || !suppliedKey || !(await constantTimeEqual(configuredKey, suppliedKey))) {
      throw new HttpError(401, "operations_authentication_required", "운영 인증이 필요합니다.");
    }
    const payload = await request.json().catch(() => ({}));
    if (typeof payload?.order_id !== "string") throw new HttpError(400, "invalid_order_id");
    audit.orderID = payload.order_id;
    if (typeof payload?.reason_code !== "string" || !allowedReasonCodes.has(payload.reason_code)) {
      throw new HttpError(400, "invalid_refund_reason", "허용된 법정 환불 사유가 필요합니다.");
    }
    if (payload?.reason_detail !== undefined && typeof payload.reason_detail !== "string") {
      throw new HttpError(400, "invalid_refund_reason_detail");
    }
    const operator = request.headers.get("x-sidey-commerce-operator")?.trim() ?? "";
    if (!/^[A-Za-z0-9._@-]{3,80}$/.test(operator)) {
      throw new HttpError(400, "invalid_refund_operator", "운영자 식별자가 필요합니다.");
    }
    const requestID = typeof payload?.request_id === "string"
      ? payload.request_id
      : crypto.randomUUID();
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(requestID)) {
      throw new HttpError(400, "invalid_refund_request_id");
    }
    const targets = await serviceRPC<RefundTarget[]>("commerce_refund_target", {
      p_order_id: payload.order_id,
      p_reason_code: payload.reason_code,
      p_request_id: requestID,
      p_requested_by: operator,
      p_reason_detail: payload.reason_detail?.trim() || null,
    });
    const target = targets[0];
    if (!target) {
      throw new HttpError(409, "refund_not_available", "승인되지 않았거나 이미 환불된 주문입니다.");
    }
    audit.requested = true;
    await assertRuntimePaymentConfiguration();

    const canceled = await tossRequest<TossPayment>(
      `/payments/${encodeURIComponent(target.payment_key)}/cancel`,
      {
        method: "POST",
        idempotencyKey: `refund-${target.request_id}`,
        body: { cancelReason: `SIDEY 법정 사유 전액 환불: ${payload.reason_code}` },
      },
    );
    if (canceled.orderId !== target.provider_order_id || canceled.totalAmount !== target.amount_krw) {
      throw new HttpError(409, "refund_verification_failed");
    }
    await serviceRPC<void>("commerce_record_refund_result", {
      p_order_id: payload.order_id,
      p_processing_status: "provider_canceled",
      p_result_code: "provider_cancel_accepted",
      p_provider_status: canceled.status,
    });
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
    await serviceRPC<void>("commerce_record_refund_result", {
      p_order_id: payload.order_id,
      p_processing_status: status === "refunded" ? "completed" : "failed",
      p_result_code: status === "refunded" ? "refund_verified" : "refund_state_not_applied",
      p_provider_status: payment.status,
    });
    return jsonResponse({
      request_id: target.request_id,
      refunded: status === "refunded",
      status,
    });
  } catch (error) {
    if (audit.requested) {
      const resultCode = error instanceof HttpError ? error.code : "refund_internal_error";
      await serviceRPC<void>("commerce_record_refund_result", {
        p_order_id: audit.orderID,
        p_processing_status: "failed",
        p_result_code: resultCode,
        p_provider_status: null,
      }).catch((auditError) => console.error("Unable to record refund failure", auditError));
    }
    return publicError(error);
  }
});
