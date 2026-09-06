export const entitlementByProduct = Object.freeze({
  character_starlight_upalupa: "character:pixel_starlight_upalupa",
  character_guinea_pig: "character:pixel_guinea_pig",
  character_monkey: "character:pixel_monkey",
  character_chinchilla: "character:pixel_chinchilla",
  bubble_bunny_pink: "bubble:bubble_bunny_pink",
  bubble_butter_chick: "bubble:bubble_butter_chick",
  bubble_starry_cat: "bubble:bubble_starry_cat",
  throwable_bouncy_heart: "throwable:throwable_bouncy_heart",
  throwable_toy_cannon: "throwable:throwable_toy_cannon",
  throwable_squeaky_duck: "throwable:throwable_squeaky_duck",
} as const);

export type SideyProductID = keyof typeof entitlementByProduct;

export function isSideyProductID(value: string): value is SideyProductID {
  return Object.hasOwn(entitlementByProduct, value);
}

export function transactionStatus(revocationDate?: number | null): "active" | "refunded" {
  return revocationDate == null ? "active" : "refunded";
}
