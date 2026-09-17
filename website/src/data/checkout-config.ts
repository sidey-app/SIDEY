import { defaultAPIBase, validateAPIBase } from "../../public/assets/checkout-api.js";

export const checkoutAPIBase = validateAPIBase(import.meta.env.PUBLIC_SIDEY_API_BASE_URL ?? defaultAPIBase);
export const checkoutAPIOrigin = new URL(checkoutAPIBase).origin;
