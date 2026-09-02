export const PRODUCT_ID = "character_starlight_upalupa";
export const TOSS_API_BASE = "https://api.tosspayments.com/v1";

export const corsHeaders = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, apikey, content-type, x-client-info",
  "access-control-allow-methods": "GET, POST, OPTIONS",
};

export class HttpError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message = code,
  ) {
    super(message);
  }
}

export class CommerceConfigurationError extends Error {
  constructor(readonly environmentName: string) {
    super(`missing_environment:${environmentName}`);
  }
}

export type CommerceOrder = {
  order_id: string;
  provider_order_id: string;
  display_name: string;
  amount_krw: number;
  currency: string;
  checkout_token_expires_at?: string;
  customer_name?: string;
  policy_version?: string;
  policy_notice?: string;
  policy_consented_at?: string | null;
  payment_environment?: CommercePaymentEnvironment;
};

export type CommercePaymentEnvironment = "test" | "live";

export type CommerceRuntimeConfiguration = {
  sales_enabled: boolean;
  payment_environment: CommercePaymentEnvironment;
  policy_version: string;
  policy_notice: string;
};

export type TossPayment = {
  paymentKey: string;
  orderId: string;
  status: string;
  currency: string;
  totalAmount: number;
  balanceAmount: number;
  lastTransactionKey?: string | null;
};

function requiredEnvironment(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new CommerceConfigurationError(name);
  return value;
}

export function supabaseURL(): string {
  return requiredEnvironment("SUPABASE_URL").replace(/\/$/, "");
}

export function functionURL(name: string): string {
  const configuredURL = Deno.env.get("SIDEY_PUBLIC_SUPABASE_URL")?.trim();
  const baseURL = new URL(configuredURL || supabaseURL());
  if (baseURL.protocol !== "http:" && baseURL.protocol !== "https:") {
    throw new CommerceConfigurationError("SIDEY_PUBLIC_SUPABASE_URL");
  }
  if (["kong", "edge-runtime"].includes(baseURL.hostname.toLowerCase())) {
    throw new CommerceConfigurationError("SIDEY_PUBLIC_SUPABASE_URL");
  }
  baseURL.pathname = `/functions/v1/${name}`;
  baseURL.search = "";
  baseURL.hash = "";
  return baseURL.toString();
}

function websitePageURL(path: string): URL {
  const base = Deno.env.get("SIDEY_WEBSITE_URL")?.trim()
    || "https://sidey-app.github.io/SIDEY/";
  const url = new URL(path, base.endsWith("/") ? base : `${base}/`);
  if (url.protocol !== "http:" && url.protocol !== "https:") {
    throw new CommerceConfigurationError("SIDEY_WEBSITE_URL");
  }
  return url;
}

export function checkoutPageURL(token: string): string {
  const url = websitePageURL("checkout.html");
  // Keep the one-time bearer token in the URL fragment so it is not sent to
  // the static host in the HTTP request or its access logs.
  url.hash = new URLSearchParams({ token }).toString();
  return url.toString();
}

export function checkoutResultURL(result: string): string {
  const url = websitePageURL("checkout-result.html");
  url.searchParams.set("result", result);
  return url.toString();
}

export function redirectResponse(location: string, status = 303): Response {
  return new Response(null, {
    status,
    headers: {
      location,
      "cache-control": "no-store",
      "referrer-policy": "no-referrer",
      "x-content-type-options": "nosniff",
    },
  });
}

export function tossClientKey(): string {
  return requiredEnvironment("TOSS_PAYMENTS_CLIENT_KEY");
}

function serviceRoleKey(): string {
  return requiredEnvironment("SUPABASE_SERVICE_ROLE_KEY");
}

function publishableKey(): string {
  return Deno.env.get("SUPABASE_ANON_KEY")?.trim()
    || requiredEnvironment("SIDEY_SUPABASE_PUBLISHABLE_KEY");
}

function tossSecretKey(): string {
  return requiredEnvironment("TOSS_PAYMENTS_SECRET_KEY");
}

function tossKeyDescriptor(
  key: string,
  kind: "client" | "secret",
): { environment: CommercePaymentEnvironment; family: "widget" | "core" } | null {
  const match = key.match(kind === "client"
    ? /^(test|live)_(gck|ck)_/
    : /^(test|live)_(gsk|sk)_/);
  if (!match) return null;
  return {
    environment: match[1] as CommercePaymentEnvironment,
    family: match[2].startsWith("g") ? "widget" : "core",
  };
}

export function assertCheckoutConfiguration(
  expectedEnvironment: CommercePaymentEnvironment,
): void {
  functionURL("commerce-checkout");
  const client = tossKeyDescriptor(tossClientKey(), "client");
  const secret = tossKeyDescriptor(tossSecretKey(), "secret");
  if (
    !client
    || !secret
    || client.environment !== secret.environment
    || client.family !== secret.family
    || client.environment !== expectedEnvironment
  ) {
    throw new CommerceConfigurationError("TOSS_PAYMENTS_KEY_PAIR");
  }
}

export async function assertRuntimePaymentConfiguration(): Promise<CommerceRuntimeConfiguration> {
  const rows = await serviceRPC<CommerceRuntimeConfiguration[]>(
    "commerce_runtime_configuration",
    {},
  );
  const runtime = rows[0];
  if (!runtime || (runtime.payment_environment !== "test" && runtime.payment_environment !== "live")) {
    throw new CommerceConfigurationError("COMMERCE_RUNTIME_SETTINGS");
  }
  assertCheckoutConfiguration(runtime.payment_environment);
  return runtime;
}

export function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
    },
  });
}

export function publicError(error: unknown): Response {
  if (error instanceof HttpError) {
    return jsonResponse({ error: error.code, message: error.message }, error.status);
  }
  if (error instanceof CommerceConfigurationError) {
    console.error(error.message);
    return jsonResponse({
      error: "commerce_not_configured",
      message: "결제 서비스가 아직 준비되지 않았습니다.",
    }, 503);
  }
  console.error(error);
  return jsonResponse({ error: "internal_error", message: "요청을 처리하지 못했습니다." }, 500);
}

export async function sha256Hex(value: string | Uint8Array): Promise<string> {
  const bytes = typeof value === "string" ? new TextEncoder().encode(value) : value;
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

export function randomToken(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

export async function authenticatedUser(authorization: string | null): Promise<{ id: string }> {
  if (!authorization?.startsWith("Bearer ")) {
    throw new HttpError(401, "authentication_required", "SIDEY 로그인이 필요합니다.");
  }
  const response = await fetch(`${supabaseURL()}/auth/v1/user`, {
    headers: { authorization, apikey: publishableKey() },
  });
  if (!response.ok) {
    throw new HttpError(401, "authentication_required", "SIDEY 로그인이 만료되었습니다.");
  }
  const user = await response.json();
  if (typeof user?.id !== "string") throw new HttpError(401, "authentication_required");
  return { id: user.id };
}

async function rpc<T>(
  name: string,
  body: Record<string, unknown>,
  authorization: string,
  apiKey: string,
): Promise<T> {
  const response = await fetch(`${supabaseURL()}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: {
      authorization,
      apikey: apiKey,
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
  });
  if (!response.ok) {
    const payload = await response.json().catch(() => ({}));
    const code = typeof payload?.message === "string" ? payload.message : "database_error";
    const status = response.status === 401 || response.status === 403 ? 403 : 400;
    throw new HttpError(status, code, code);
  }
  return await response.json() as T;
}

export function userRPC<T>(
  name: string,
  body: Record<string, unknown>,
  authorization: string,
): Promise<T> {
  return rpc(name, body, authorization, publishableKey());
}

export function serviceRPC<T>(name: string, body: Record<string, unknown>): Promise<T> {
  const key = serviceRoleKey();
  return rpc(name, body, `Bearer ${key}`, key);
}

function tossAuthorization(): string {
  return `Basic ${btoa(`${tossSecretKey()}:`)}`;
}

export async function tossRequest<T>(
  path: string,
  options: { method?: "GET" | "POST"; body?: unknown; idempotencyKey?: string } = {},
): Promise<T> {
  const headers: Record<string, string> = {
    authorization: tossAuthorization(),
    "content-type": "application/json",
  };
  if (options.idempotencyKey) headers["Idempotency-Key"] = options.idempotencyKey;
  const response = await fetch(`${TOSS_API_BASE}${path}`, {
    method: options.method ?? "GET",
    headers,
    body: options.body === undefined ? undefined : JSON.stringify(options.body),
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    console.error("Toss Payments request failed", response.status, payload?.code);
    throw new HttpError(502, "payment_provider_error", "결제사 응답을 확인하지 못했습니다.");
  }
  return payload as T;
}

export function validatePayment(payment: TossPayment, expected: CommerceOrder): TossPayment {
  if (
    payment.orderId !== expected.provider_order_id
    || payment.totalAmount !== expected.amount_krw
    || payment.currency !== expected.currency
    || typeof payment.paymentKey !== "string"
    || payment.paymentKey.length < 10
  ) {
    throw new HttpError(409, "payment_verification_failed", "결제 정보가 주문과 일치하지 않습니다.");
  }
  return payment;
}

export async function constantTimeEqual(left: string, right: string): Promise<boolean> {
  const [leftHash, rightHash] = await Promise.all([sha256Hex(left), sha256Hex(right)]);
  let difference = 0;
  for (let index = 0; index < leftHash.length; index += 1) {
    difference |= leftHash.charCodeAt(index) ^ rightHash.charCodeAt(index);
  }
  return difference === 0;
}
