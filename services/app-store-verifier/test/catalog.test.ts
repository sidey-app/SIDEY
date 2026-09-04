import assert from "node:assert/strict";
import test from "node:test";
import { entitlementByProduct, isSideyProductID, transactionStatus } from "../src/catalog.js";

test("catalog maps exactly the four SIDEY App Store products", () => {
  assert.deepEqual(entitlementByProduct, {
    character_starlight_upalupa: "character:pixel_starlight_upalupa",
    character_guinea_pig: "character:pixel_guinea_pig",
    character_monkey: "character:pixel_monkey",
    character_chinchilla: "character:pixel_chinchilla",
  });
  assert.equal(isSideyProductID("character_monkey"), true);
  assert.equal(isSideyProductID("character_unknown"), false);
});

test("a revocation date makes a non-consumable transaction refunded", () => {
  assert.equal(transactionStatus(null), "active");
  assert.equal(transactionStatus(undefined), "active");
  assert.equal(transactionStatus(Date.now()), "refunded");
});
