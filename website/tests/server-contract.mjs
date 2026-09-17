// Opt-in real Spring check. Run only against an isolated local instance without
// provider configuration; this script never submits a payment or identity proof.
import assert from "node:assert/strict";
import { commerceRequest, checkoutFailureMessage, validateAPIBase } from "../public/assets/checkout-api.js";

const apiBase = validateAPIBase(process.env.SIDEY_TEST_API_BASE_URL);
assert.ok(["localhost", "127.0.0.1", "[::1]"].includes(new URL(apiBase).hostname), "requires isolated loopback backend");
const origin = "https://sidey-app.github.io";
const preflight = await fetch(`${apiBase}/commerce/checkout`, {
  method: "OPTIONS",
  headers: { Origin: origin, "Access-Control-Request-Method": "POST", "Access-Control-Request-Headers": "content-type" },
});
assert.equal(preflight.status, 200);
assert.equal(preflight.headers.get("access-control-allow-origin"), origin);
const foreign = await fetch(`${apiBase}/commerce/checkout`, {
  method: "OPTIONS",
  headers: { Origin: "https://untrusted.example", "Access-Control-Request-Method": "POST" },
});
assert.equal(foreign.status, 403);
assert.equal(foreign.headers.get("access-control-allow-origin"), null);
await assert.rejects(
  commerceRequest({ fetch }, apiBase, "checkout", { token: "invalid", action: "prepare" }),
  failure => failure.status === 503 && failure.code === "commerce_not_configured" && checkoutFailureMessage(failure).includes("지금은 결제를"),
);
await assert.rejects(
  commerceRequest({ fetch }, apiBase, "complete", { token: "invalid", paymentId: "invalid" }),
  failure => failure.status === 400 && failure.code === "invalid_checkout_token",
);
console.log("PASS: actual Spring checkout CORS, provider-unavailable, invalid-token responses through production browser transport");
