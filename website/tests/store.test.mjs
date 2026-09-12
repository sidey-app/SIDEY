import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync, existsSync } from "node:fs";

const catalog = JSON.parse(readFileSync(new URL("../../assets/v1/commerce-catalog.json", import.meta.url)));
const read = (path) => readFileSync(new URL(`../dist/${path}`, import.meta.url), "utf8");
const root = new URL("../../", import.meta.url);
const included = { characters: 5, throwables: 1, bubbles: 1 };

for (const locale of ["ko", "en", "ja"]) {
  for (const category of Object.keys(included)) {
    test(`${locale}/${category}: complete catalog, exact direct prices, assets, separate keepsakes`, () => {
      const html = read(`${locale}/store/${category}/index.html`);
      const cards = [...html.matchAll(/<button class="store-product-card"[^>]*>[\s\S]*?<\/button>/g)].map(([card]) => card);
      const paid = catalog.filter((entry) => entry.kind === category.slice(0, -1));
      assert.equal(cards.length, paid.length + included[category]);
      assert.match(html, /store-price-basis/);
      assert.match(html, /App Store/);
      for (const entry of paid) {
        const card = cards.find((candidate) => candidate.includes(`data-product-id="${entry.id}"`));
        assert.ok(card, entry.id);
        const price = locale === "ko" ? `${entry.direct_price.toLocaleString("ko-KR")}원` : `₩${entry.direct_price.toLocaleString("en-US")}`;
        assert.ok(card.includes(`<strong>${price}</strong>`), `${entry.id}: ${price}`);
        if (locale === "ko") assert.ok(card.includes(entry.name));
        const keepsake = catalog.find((candidate) => candidate.related_character_product_id === entry.id);
        if (keepsake) {
          assert.match(card, /store-keepsake-summary/);
          assert.match(card, /store-keepsake-badge/);
          assert.ok(html.includes(`id="details-${keepsake.item_id}"`), "keepsake transition retains its price details");
        }
        if (entry.related_character_product_id) assert.match(card, /store-keepsake-badge/);
      }
      for (const [, path] of html.matchAll(/(?:src|data-preview-src|data-preview-emitter|data-preview-sound)="\/SIDEY\/([^"?#]+)"/g)) {
        assert.ok(existsSync(new URL(`../dist/${path}`, import.meta.url)), path);
      }
      assert.doesNotMatch(html, /production|staging|Sidey-dev|출시 예정|준비 중|checkout\?token=/);
      if (category === "characters") {
        assert.equal(html.match(/class="store-keepsake-summary"/g)?.length, 7);
        if (locale === "ko") assert.match(html, /우클릭하면 멈추고/);
      }
    });
  }
  test(`${locale}: store entry and character tab show the same products`, () => {
    const ids = (html) => [...html.matchAll(/<button class="store-product-card"[^>]*data-product-id="([^"]+)"/g)].map((match) => match[1]);
    assert.deepEqual(ids(read(`${locale}/store/index.html`)), ids(read(`${locale}/store/characters/index.html`)));
  });
}

test("public sheets and sounds exactly match the approved canonical assets", () => {
  for (const entry of catalog.filter((entry) => entry.kind !== "bubble")) {
    const id = entry.render_asset_id ?? entry.item_id;
    const source = entry.kind === "character" ? `characters/${id}/base.png` : `throwables/${id}/sprite.png`;
    assert.deepEqual(readFileSync(new URL(`website/public/assets/store/${id}.png`, root)), readFileSync(new URL(`assets/v1/${source}`, root)));
  }
  for (const id of ["clam", "pork", "timber", "throwable_snowflake", "throwable_baseball", "throwable_wakkuball", "throwable_dujjonku"]) {
    const path = `impact-${id}.wav`;
    assert.deepEqual(readFileSync(new URL(`website/public/assets/store/${path}`, root)), readFileSync(new URL(`assets/v1/audio/${path}`, root)));
    assert.ok(read("ko/store/throwables/index.html").includes(`data-preview-sound="/SIDEY/assets/store/${path}"`));
  }
});

test("checkout and store share all current products and correct base-relative image URLs", async () => {
  const { commerceProducts } = await import("../public/assets/commerce-products.js");
  assert.deepEqual(Object.keys(commerceProducts).sort(), catalog.map(p => p.id).sort());
  for (const entry of catalog) {
    const product = commerceProducts[entry.id];
    assert.equal(product.name, entry.name);
    assert.ok(existsSync(new URL(`website/public/${product.image}`, root)), product.image);
    for (const base of ["https://example.test/SIDEY/", "https://example.test/"]) {
      const url = new URL(`../${product.image}`, `${base}assets/checkout.js`);
      assert.equal(url.href, base + product.image);
    }
  }
  for (const page of ["checkout", "checkout-result"]) {
    assert.match(read(`${page}/index.html`), new RegExp(`type="module"[^>]*src="[^\"]*${page}\\.js"|src="[^\"]*${page}\\.js"[^>]*type="module"`));
  }
});
