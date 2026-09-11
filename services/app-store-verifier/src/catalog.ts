// Current sale offers and historical restore-only offers. Keep aligned with commerce-catalog.json.
export const entitlementByProduct = Object.freeze({
  character_starlight_upalupa_solo: "character:pixel_starlight_upalupa",
  character_starlight_upalupa: "character:pixel_starlight_upalupa",
  character_guinea_pig_solo: "character:pixel_guinea_pig",
  character_guinea_pig: "character:pixel_guinea_pig",
  character_monkey_solo: "character:pixel_monkey",
  character_monkey: "character:pixel_monkey",
  character_chinchilla_solo: "character:pixel_chinchilla",
  character_chinchilla: "character:pixel_chinchilla",
  bubble_bunny_pink: "bubble:bubble_bunny_pink",
  bubble_butter_chick: "bubble:bubble_butter_chick",
  bubble_starry_cat: "bubble:bubble_starry_cat",
  throwable_bouncy_heart: "throwable:throwable_bouncy_heart",
  throwable_toy_cannon: "throwable:throwable_toy_cannon",
  throwable_squeaky_duck: "throwable:throwable_squeaky_duck",
  character_otter: "character:pixel_otter",
  character_pig: "character:pixel_pig",
  character_tree: "character:pixel_tree",
  throwable_snowflake: "throwable:throwable_snowflake",
  throwable_baseball: "throwable:throwable_baseball",
  throwable_wakkuball: "throwable:throwable_wakkuball",
  throwable_dujjonku: "throwable:throwable_dujjonku",
  throwable_mini_paprika: "throwable:throwable_mini_paprika",
  throwable_banana: "throwable:throwable_banana",
  throwable_dust_bath_pouch: "throwable:throwable_dust_bath_pouch",
  throwable_starlight_orb: "throwable:throwable_starlight_orb",
  throwable_clam: "throwable:throwable_clam",
  throwable_pork: "throwable:throwable_pork",
  throwable_timber: "throwable:throwable_timber",
} as const);

export type SideyProductID = keyof typeof entitlementByProduct;

export function isSideyProductID(value: string): value is SideyProductID {
  return Object.hasOwn(entitlementByProduct, value);
}

export function transactionStatus(revocationDate?: number | null): "active" | "refunded" {
  return revocationDate == null ? "active" : "refunded";
}
