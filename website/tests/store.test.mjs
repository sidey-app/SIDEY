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
      if (category === "throwables") {
        for (const card of cards) assert.match(card, /data-preview-sound="[^"]+\.wav"/);
        const soundButton = html.match(/<button[^>]*data-store-preview-sound-toggle[^>]*>[\s\S]*?<\/button>/)?.[0];
        assert.ok(soundButton);
        assert.match(soundButton, /aria-pressed="false"/);
        assert.match(soundButton, /<svg[^>]*viewBox="0 0 24 24"/);
        assert.doesNotMatch(soundButton, /material-symbols|volume_off|volume_up/);
      }
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
  const throwableIDs = ["patch_soft_ball", ...catalog.filter(entry => entry.kind === "throwable").map(entry => entry.render_asset_id ?? entry.item_id)];
  for (const id of throwableIDs) {
    const path = `impact-${id}.wav`;
    const publicAudio = readFileSync(new URL(`website/public/assets/store/${path}`, root));
    assert.deepEqual(publicAudio, readFileSync(new URL(`macos/SIDEY/Resources/DirectImpactAudio/${path}`, root)));
    const canonical = new URL(`assets/v1/audio/${path}`, root);
    if (existsSync(canonical)) assert.deepEqual(publicAudio, readFileSync(canonical));
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

test("preview sound responds to clicks, motion preference, product changes and dismissal", async () => {
  const { runInNewContext } = await import("node:vm");
  class Element {
    dataset = {}; listeners = {}; attributes = {}; children = [];
    classList = { add() {}, toggle() {} };
    addEventListener(name, fn) { this.listeners[name] = fn; }
    setAttribute(name, value) { this.attributes[name] = value; }
    appendChild(child) { this.children.push(child); }
    append(...children) { this.children.push(...children); }
    replaceChildren(...children) { this.children = children; }
    closest() { return this; }
    focus() {}
  }
  class Dialog extends Element {
    open = false;
    showModal() { this.open = true; }
    close() { this.open = false; this.listeners.close(); }
  }
  const dialog = new Dialog();
  const controls = Object.fromEntries(["stage", "title", "description", "close", "details", "sound-toggle"].map(key => [`[data-store-preview-${key}]`, new Element()]));
  dialog.querySelector = selector => controls[selector];
  const sound = controls["[data-store-preview-sound-toggle]"];
  const stage = controls["[data-store-preview-stage]"];
  const document = {
    hidden: false, documentElement: { dataset: { baseUrl: "/SIDEY/" } }, listeners: {},
    querySelectorAll: () => [], getElementById: id => id === "store-preview-dialog" ? dialog : null,
    createElement: () => new Element(), addEventListener(name, fn) { this.listeners[name] = fn; },
  };
  const players = [];
  class Audio {
    plays = 0; pauses = 0;
    constructor(source) { this.source = source; players.push(this); }
    play() { this.plays++; return new Promise((resolve, reject) => { this.reject = reject; }); }
    pause() { this.pauses++; }
  }
  const timers = new Map();
  let timerID = 0;
  let reducedMotion = true;
  const window = {
    matchMedia: () => ({ matches: reducedMotion }),
    setTimeout: fn => { timers.set(++timerID, fn); return timerID; },
    clearTimeout: id => timers.delete(id),
  };
  runInNewContext(readFileSync(new URL("../public/assets/store.js", import.meta.url), "utf8"), {
    document, window, Element, HTMLDialogElement: Dialog, HTMLTemplateElement: class {}, Audio,
  });
  const open = (soundPath, kind = "throwable") => {
    const target = new Element();
    target.dataset = { previewKind: kind, previewSrc: "sprite.png", previewSound: soundPath };
    document.listeners.click({ target });
  };
  open("ball.wav");
  assert.equal(sound.hidden, false);
  assert.equal(players[0].plays, 0, "default is silent");
  sound.listeners.click();
  assert.equal(players[0].plays, 1, "explicit click works even with reduced motion");
  assert.equal(sound.attributes["aria-pressed"], "true");
  open("duck.wav");
  assert.equal(players[0].pauses, 1, "switching products stops the previous sound");
  players[0].reject(new Error("old playback interrupted"));
  await Promise.resolve();
  assert.equal(sound.attributes["aria-pressed"], "true", "old audio failure cannot mute the new product");
  reducedMotion = false;
  const projectile = stage.children[1];
  projectile.listeners.animationiteration({ target: projectile, animationName: "preview-throw-arc" });
  [...timers.values()].at(-1)();
  assert.equal(players[1].plays, 1, "subsequent collisions play the selected sound");
  sound.listeners.click();
  assert.equal(players[1].pauses, 1);
  assert.equal(sound.attributes["aria-pressed"], "false");
  sound.listeners.click();
  document.hidden = true;
  document.listeners.visibilitychange();
  assert.equal(players[1].pauses, 2);
  document.hidden = false;
  controls["[data-store-preview-close]"].listeners.click();
  assert.equal(players[1].pauses, 3);
  [...timers.values()].at(-1)();
  assert.equal(dialog.open, false);
  open(undefined, "character");
  assert.equal(sound.hidden, true, "characters do not expose a sound toggle");
});
