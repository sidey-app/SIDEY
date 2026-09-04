export const entitlementByProduct = Object.freeze({
  character_starlight_upalupa: "character:pixel_starlight_upalupa",
  character_guinea_pig: "character:pixel_guinea_pig",
  character_monkey: "character:pixel_monkey",
  character_chinchilla: "character:pixel_chinchilla",
} as const);

export type SideyProductID = keyof typeof entitlementByProduct;

export function isSideyProductID(value: string): value is SideyProductID {
  return Object.hasOwn(entitlementByProduct, value);
}

export function transactionStatus(revocationDate?: number | null): "active" | "refunded" {
  return revocationDate == null ? "active" : "refunded";
}
