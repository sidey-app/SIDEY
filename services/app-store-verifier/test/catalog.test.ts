import assert from "node:assert/strict";
import test from "node:test";
import { entitlementByProduct, isSideyProductID, transactionStatus } from "../src/catalog.js";

test("catalog maps exactly the ten SIDEY App Store products", () => {
  assert.deepEqual(entitlementByProduct, {
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
  });
  assert.equal(isSideyProductID("character_monkey"), true);
  assert.equal(isSideyProductID("bubble_starry_cat"), true);
  assert.equal(isSideyProductID("throwable_toy_cannon"), true);
  assert.equal(isSideyProductID("character_unknown"), false);
});

test("a revocation date makes a non-consumable transaction refunded", () => {
  assert.equal(transactionStatus(null), "active");
  assert.equal(transactionStatus(undefined), "active");
  assert.equal(transactionStatus(Date.now()), "refunded");
});
