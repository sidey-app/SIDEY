import commerceCatalog from "../../../assets/v1/commerce-catalog.json";
import { paidTranslations } from "./store-translations";
import type { Locale } from "../i18n/landing";

export type StoreCategory = "characters" | "throwables" | "bubbles";
export type StoreAssetMode = "character" | "throwable" | "cannon" | "bubble";

export interface StoreProduct {
  id: string;
  name: string;
  description: string;
  price: string;
  commerceID?: string;
  keepsake?: StoreProduct;
  sound?: string;
  isKeepsake?: boolean;
  isTree?: boolean;
  asset?: string;
  mode: StoreAssetMode;
  previewAsset?: string;
  emitterAsset?: string;
  mirrorsMovement?: boolean;
  bubbleTheme?: "default" | "bunny-pink" | "butter-chick" | "starry-cat";
}

export interface StoreCategoryContent {
  eyebrow: string;
  title: string;
  description: string;
  products: StoreProduct[];
}

export type StoreCatalog = Record<StoreCategory, StoreCategoryContent>;

const ko: StoreCatalog = {
  characters: {
    eyebrow: "캐릭터",
    title: "화면에 데려올 새 친구들.",
    description: "캐릭터를 누르면 실제 SIDEY에서 움직이는 모습을 먼저 볼 수 있어요.",
    products: [
      { id: "pixel_hamster", name: "아기 햄스터", description: "작은 귀와 분홍 볼을 가진 SIDEY의 기본 친구예요.", price: "기본 제공", asset: "assets/characters/pixel_hamster.png", mode: "character" },
      { id: "pixel_cat", name: "아기 고양이", description: "회색 줄무늬와 뾰족한 귀가 귀여운 친구예요.", price: "기본 제공", asset: "assets/characters/pixel_cat.png", mode: "character" },
      { id: "pixel_puppy", name: "복실 강아지", description: "카라멜빛 귀와 복슬복슬한 얼굴을 가진 친구예요.", price: "기본 제공", asset: "assets/characters/pixel_puppy.png", mode: "character" },
      { id: "pixel_rabbit", name: "아기 토끼", description: "긴 귀와 보랏빛 목도리가 잘 어울리는 친구예요.", price: "기본 제공", asset: "assets/characters/pixel_rabbit.png", mode: "character" },
      { id: "pixel_penguin", name: "꼬마 펭귄", description: "남색 몸과 민트색 목도리로 종종 걸어요.", price: "기본 제공", asset: "assets/characters/pixel_penguin.png", mode: "character" },
      { id: "pixel_starlight_upalupa", name: "별빛 우파루파", description: "진주빛 몸과 별빛 아가미를 가진 작은 친구예요.", price: "1,900원", asset: "assets/characters/pixel_starlight_upalupa.png", mode: "character", mirrorsMovement: true },
      { id: "pixel_guinea_pig", name: "아기 기니피그", description: "둥글고 포동포동한 삼색 무늬가 매력인 친구예요.", price: "990원", asset: "assets/characters/pixel_guinea_pig.png", mode: "character", mirrorsMovement: true },
      { id: "pixel_monkey", name: "아기 원숭이", description: "밤갈색 머리털과 시안 목도리로 씩씩하게 걸어요.", price: "990원", asset: "assets/characters/pixel_monkey.png", mode: "character" },
      { id: "pixel_chinchilla", name: "아기 친칠라", description: "크고 둥근 귀와 폭신한 회색 털을 가진 친구예요.", price: "990원", asset: "assets/characters/pixel_chinchilla.png", mode: "character" },
    ],
  },
  throwables: {
    eyebrow: "투척물",
    title: "말랑공부터 미니 대포까지.",
    description: "말랑공, 하트, 미니 대포처럼 친구에게 던질 수 있는 장난들을 먼저 구경해 보세요.",
    products: [
      { id: "patch_soft_ball", name: "패치 말랑공", description: "기본 캐릭터들이 친구에게 가볍게 던지는 말랑공이에요.", price: "기본 제공", asset: "assets/previewer/patch_soft_ball.png", mode: "throwable" },
      { id: "throwable_bouncy_heart", name: "통통 하트", description: "통통 튀며 날아가 마음을 전하는 하트예요.", price: "990원", asset: "assets/cosmetics/throwable_bouncy_heart.png", mode: "throwable" },
      { id: "throwable_toy_cannon", name: "미니 대포", description: "캐릭터 옆에 대포가 나타나 힘차게 한 발을 쏘아 올려요.", price: "2,900원", asset: "assets/cosmetics/throwable_toy_cannon_sprite.png", emitterAsset: "assets/cosmetics/throwable_toy_cannon_emitter.png", mode: "cannon" },
      { id: "throwable_squeaky_duck", name: "삑삑 오리", description: "노란 오리가 빙글빙글 날아가는 장난스러운 투척물이에요.", price: "990원", asset: "assets/cosmetics/throwable_squeaky_duck.png", mode: "throwable" },
    ],
  },
  bubbles: {
    eyebrow: "말풍선",
    title: "말풍선도 내 취향대로.",
    description: "메시지와 입력 중 표시의 색과 작은 장식을 바꿀 수 있어요.",
    products: [
      { id: "bubble_default", name: "기본 말풍선", description: "어떤 화면에서도 또렷하게 읽히는 SIDEY의 기본 말풍선이에요.", price: "기본 제공", mode: "bubble", bubbleTheme: "default" },
      { id: "bubble_bunny_pink", name: "핑크 토끼 말풍선", description: "토끼 장식과 또렷한 진한 글자가 있는 분홍 말풍선이에요.", price: "1,900원", asset: "assets/cosmetics/bubble_bunny_pink_decoration.png", mode: "bubble", bubbleTheme: "bunny-pink" },
      { id: "bubble_butter_chick", name: "버터 병아리 말풍선", description: "병아리 장식과 진한 글자가 있는 버터색 말풍선이에요.", price: "1,900원", asset: "assets/cosmetics/bubble_butter_chick_decoration.png", mode: "bubble", bubbleTheme: "butter-chick" },
      { id: "bubble_starry_cat", name: "별밤 고양이 말풍선", description: "별고양이 장식과 밝은 글자가 있는 남보라 말풍선이에요.", price: "1,900원", asset: "assets/cosmetics/bubble_starry_cat_decoration.png", mode: "bubble", bubbleTheme: "starry-cat" },
    ],
  },
};

const en: StoreCatalog = {
  characters: {
    eyebrow: "Characters",
    title: "New friends for your screen.",
    description: "Open a preview to see how each character moves in SIDEY.",
    products: [
      { id: "pixel_hamster", name: "Baby Hamster", description: "SIDEY's original companion, with tiny ears and rosy cheeks.", price: "Included", asset: "assets/characters/pixel_hamster.png", mode: "character" },
      { id: "pixel_cat", name: "Baby Cat", description: "A soft gray tabby with a pair of perfectly pointy ears.", price: "Included", asset: "assets/characters/pixel_cat.png", mode: "character" },
      { id: "pixel_puppy", name: "Fluffy Puppy", description: "A caramel-eared pup with a wonderfully fluffy face.", price: "Included", asset: "assets/characters/pixel_puppy.png", mode: "character" },
      { id: "pixel_rabbit", name: "Baby Rabbit", description: "Long ears and a violet scarf make this little friend easy to spot.", price: "Included", asset: "assets/characters/pixel_rabbit.png", mode: "character" },
      { id: "pixel_penguin", name: "Little Penguin", description: "A navy penguin who waddles along in a mint scarf.", price: "Included", asset: "assets/characters/pixel_penguin.png", mode: "character" },
      { id: "pixel_starlight_upalupa", name: "Starlight Axolotl", description: "A pearl-bright friend with shimmering, starry gills.", price: "₩1,900", asset: "assets/characters/pixel_starlight_upalupa.png", mode: "character", mirrorsMovement: true },
      { id: "pixel_guinea_pig", name: "Baby Guinea Pig", description: "Round, cozy, and dressed in three-color patches.", price: "₩990", asset: "assets/characters/pixel_guinea_pig.png", mode: "character", mirrorsMovement: true },
      { id: "pixel_monkey", name: "Baby Monkey", description: "A bright little walker with chestnut fur and a cyan scarf.", price: "₩990", asset: "assets/characters/pixel_monkey.png", mode: "character" },
      { id: "pixel_chinchilla", name: "Baby Chinchilla", description: "Big round ears and cloud-soft gray fur in one tiny companion.", price: "₩990", asset: "assets/characters/pixel_chinchilla.png", mode: "character" },
    ],
  },
  throwables: {
    eyebrow: "Throwables",
    title: "From soft balls to mini cannons.",
    description: "Preview the little things you can throw at your friends, from soft balls and hearts to mini cannons.",
    products: [
      { id: "patch_soft_ball", name: "Patch Soft Ball", description: "The soft little ball every SIDEY character can toss at a friend.", price: "Included", asset: "assets/previewer/patch_soft_ball.png", mode: "throwable" },
      { id: "throwable_bouncy_heart", name: "Bouncy Heart", description: "A cheerful heart that bounces its way across the screen.", price: "₩990", asset: "assets/cosmetics/throwable_bouncy_heart.png", mode: "throwable" },
      { id: "throwable_toy_cannon", name: "Toy Cannon", description: "A pocket-size cannon appears beside your character and fires one bold shot.", price: "₩2,900", asset: "assets/cosmetics/throwable_toy_cannon_sprite.png", emitterAsset: "assets/cosmetics/throwable_toy_cannon_emitter.png", mode: "cannon" },
      { id: "throwable_squeaky_duck", name: "Squeaky Duck", description: "A sunny yellow duck that spins through the air with comic flair.", price: "₩990", asset: "assets/cosmetics/throwable_squeaky_duck.png", mode: "throwable" },
    ],
  },
  bubbles: {
    eyebrow: "Bubbles",
    title: "Make your bubbles your own.",
    description: "Change the colors and small decorations on messages and typing indicators.",
    products: [
      { id: "bubble_default", name: "Classic Bubble", description: "SIDEY's crisp, easy-to-read bubble for every desktop.", price: "Included", mode: "bubble", bubbleTheme: "default" },
      { id: "bubble_bunny_pink", name: "Pink Bunny Bubble", description: "A rosy bubble with a tiny bunny and clear dark lettering.", price: "₩1,900", asset: "assets/cosmetics/bubble_bunny_pink_decoration.png", mode: "bubble", bubbleTheme: "bunny-pink" },
      { id: "bubble_butter_chick", name: "Butter Chick Bubble", description: "A warm butter-yellow bubble topped by a sunny little chick.", price: "₩1,900", asset: "assets/cosmetics/bubble_butter_chick_decoration.png", mode: "bubble", bubbleTheme: "butter-chick" },
      { id: "bubble_starry_cat", name: "Starry Cat Bubble", description: "A midnight-violet bubble with a starry cat and soft cream text.", price: "₩1,900", asset: "assets/cosmetics/bubble_starry_cat_decoration.png", mode: "bubble", bubbleTheme: "starry-cat" },
    ],
  },
};

const ja: StoreCatalog = {
  characters: {
    eyebrow: "キャラクター",
    title: "画面に迎える、新しい友だち。",
    description: "キャラクターを選ぶと、SIDEYで歩く様子をプレビューできます。",
    products: [
      { id: "pixel_hamster", name: "ベビーハムスター", description: "小さな耳と桃色のほっぺが目印の、SIDEYの定番キャラクターです。", price: "基本付属", asset: "assets/characters/pixel_hamster.png", mode: "character" },
      { id: "pixel_cat", name: "こねこ", description: "やわらかな灰色のしま模様と、ぴんとした耳がかわいいキャラクターです。", price: "基本付属", asset: "assets/characters/pixel_cat.png", mode: "character" },
      { id: "pixel_puppy", name: "ふわふわ子犬", description: "キャラメル色の耳と、ふわふわの顔が愛らしいキャラクターです。", price: "基本付属", asset: "assets/characters/pixel_puppy.png", mode: "character" },
      { id: "pixel_rabbit", name: "こうさぎ", description: "長い耳と紫色のマフラーがよく似合う、小さな友だちです。", price: "基本付属", asset: "assets/characters/pixel_rabbit.png", mode: "character" },
      { id: "pixel_penguin", name: "ちびペンギン", description: "紺色の体にミント色のマフラーを巻いて、ちょこちょこ歩きます。", price: "基本付属", asset: "assets/characters/pixel_penguin.png", mode: "character" },
      { id: "pixel_starlight_upalupa", name: "星明かりのウーパールーパー", description: "真珠のような体と、星明かりをまとったえらがきらめく友だちです。", price: "₩1,900", asset: "assets/characters/pixel_starlight_upalupa.png", mode: "character", mirrorsMovement: true },
      { id: "pixel_guinea_pig", name: "こどもモルモット", description: "ころんとした体と、あたたかな三色の模様が魅力です。", price: "₩990", asset: "assets/characters/pixel_guinea_pig.png", mode: "character", mirrorsMovement: true },
      { id: "pixel_monkey", name: "こざる", description: "栗色の毛とシアンのマフラーで、元気よく歩きます。", price: "₩990", asset: "assets/characters/pixel_monkey.png", mode: "character" },
      { id: "pixel_chinchilla", name: "こどもチンチラ", description: "大きく丸い耳と、雲のようにやわらかな灰色の毛が自慢です。", price: "₩990", asset: "assets/characters/pixel_chinchilla.png", mode: "character" },
    ],
  },
  throwables: {
    eyebrow: "投げアイテム",
    title: "やわらかボールからミニ大砲まで。",
    description: "ボールやハート、ミニ大砲など、友だちに送れる小さないたずらをプレビューできます。",
    products: [
      { id: "patch_soft_ball", name: "パッチやわらかボール", description: "どの基本キャラクターでも、友だちにぽんと投げられるやわらかなボールです。", price: "基本付属", asset: "assets/previewer/patch_soft_ball.png", mode: "throwable" },
      { id: "throwable_bouncy_heart", name: "はずむハート", description: "画面をぴょんぴょん弾みながら、気持ちを届けるハートです。", price: "₩990", asset: "assets/cosmetics/throwable_bouncy_heart.png", mode: "throwable" },
      { id: "throwable_toy_cannon", name: "ミニ大砲", description: "キャラクターの隣に小さな大砲が現れ、元気よく一発を撃ち出します。", price: "₩2,900", asset: "assets/cosmetics/throwable_toy_cannon_sprite.png", emitterAsset: "assets/cosmetics/throwable_toy_cannon_emitter.png", mode: "cannon" },
      { id: "throwable_squeaky_duck", name: "ピヨピヨアヒル", description: "黄色いアヒルがくるくる回りながら飛んでいく、愉快な投げアイテムです。", price: "₩990", asset: "assets/cosmetics/throwable_squeaky_duck.png", mode: "throwable" },
    ],
  },
  bubbles: {
    eyebrow: "吹き出し",
    title: "吹き出しも、自分らしく。",
    description: "メッセージや入力中表示の色と、小さな飾りを変えられます。",
    products: [
      { id: "bubble_default", name: "基本の吹き出し", description: "どんな画面でも読みやすい、SIDEYの標準吹き出しです。", price: "基本付属", mode: "bubble", bubbleTheme: "default" },
      { id: "bubble_bunny_pink", name: "ピンクうさぎの吹き出し", description: "小さなうさぎを添えた、濃い文字が読みやすい桃色の吹き出しです。", price: "₩1,900", asset: "assets/cosmetics/bubble_bunny_pink_decoration.png", mode: "bubble", bubbleTheme: "bunny-pink" },
      { id: "bubble_butter_chick", name: "バターひよこの吹き出し", description: "明るいひよこを添えた、あたたかなバター色の吹き出しです。", price: "₩1,900", asset: "assets/cosmetics/bubble_butter_chick_decoration.png", mode: "bubble", bubbleTheme: "butter-chick" },
      { id: "bubble_starry_cat", name: "星空ねこの吹き出し", description: "星空のねこを添えた、やさしいクリーム色の文字が映える夜色の吹き出しです。", price: "₩1,900", asset: "assets/cosmetics/bubble_starry_cat_decoration.png", mode: "bubble", bubbleTheme: "starry-cat" },
    ],
  },
};

// The same paid catalog drives the app, server, and public store. Never fall back
// to a different locale for a newly added product: a missing translation fails the build.
function completeCatalog(locale: Locale, catalog: StoreCatalog): StoreCatalog {
  for (const category of ["characters", "throwables", "bubbles"] as const) {
    const kind = category.slice(0, -1);
    const previous = catalog[category].products;
    const paid = commerceCatalog.filter((entry) => entry.kind === kind).sort((a, b) => a.sort_order - b.sort_order);
    const included = previous.filter((product) => !paid.some((entry) => entry.item_id === product.id));
    catalog[category].products = [...included, ...paid.map((entry): StoreProduct => {
      const existing = previous.find((product) => product.id === entry.item_id);
      const translated = locale === "ko" ? [entry.name, entry.description] : paidTranslations[locale][entry.id];
      if (!translated && !existing) throw new Error(`Missing ${locale} store translation: ${entry.id}`);
      const renderID = entry.render_asset_id ?? entry.item_id;
      return {
        ...existing,
        id: entry.item_id,
        commerceID: entry.id,
        name: translated?.[0] ?? existing!.name,
        description: translated?.[1] ?? existing!.description,
        price: locale === "ko" ? `${entry.direct_price.toLocaleString("ko-KR")}원` : `₩${entry.direct_price.toLocaleString("en-US")}`,
        mode: existing?.mode ?? (kind === "character" ? "character" : "throwable"),
        asset: kind === "bubble" ? existing?.asset : `assets/store/${renderID}.png`,
        mirrorsMovement: existing?.mirrorsMovement,
        isTree: entry.item_id === "pixel_tree",
        isKeepsake: Boolean(entry.related_character_product_id),
        sound: ["clam", "pork", "timber", "throwable_snowflake", "throwable_baseball", "throwable_wakkuball", "throwable_dujjonku"].includes(renderID) ? `assets/store/impact-${renderID}.wav` : undefined,
      };
    })];
  }
  for (const character of catalog.characters.products) {
    const paired = commerceCatalog.find((entry) => entry.related_character_product_id === character.commerceID);
    character.keepsake = paired ? catalog.throwables.products.find((product) => product.commerceID === paired.id) : undefined;
  }
  return catalog;
}

export const storeCategoriesByLocale: Record<Locale, StoreCatalog> = {
  ko: completeCatalog("ko", ko), en: completeCatalog("en", en), ja: completeCatalog("ja", ja),
};
export const storeCategories = storeCategoriesByLocale.ko;

export function getStoreCategories(locale: Locale): StoreCatalog {
  return storeCategoriesByLocale[locale];
}
