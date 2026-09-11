import type { Locale } from "../i18n/landing";

export type StoreCategory = "characters" | "throwables" | "bubbles";
export type StoreAssetMode = "character" | "throwable" | "cannon" | "bubble";

export interface StoreProduct {
  id: string;
  name: string;
  description: string;
  price: string;
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

const paidCharacter = (id: string, name: string, description: string, price: string): StoreProduct => ({
  id,
  name,
  description,
  price,
  asset: `assets/characters/${id}.png`,
  mode: "character",
});

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
      { id: "pixel_guinea_pig", name: "아기 기니피그", description: "둥글고 포동포동한 갈색 무늬가 매력인 친구예요.", price: "990원", asset: "assets/characters/pixel_guinea_pig.png", mode: "character", mirrorsMovement: true },
      { id: "pixel_monkey", name: "아기 원숭이", description: "밤갈색 머리털과 빨간 목도리로 씩씩하게 걸어요.", price: "990원", asset: "assets/characters/pixel_monkey.png", mode: "character" },
      { id: "pixel_chinchilla", name: "아기 친칠라", description: "크고 둥근 귀와 폭신한 회색 털을 가진 친구예요.", price: "990원", asset: "assets/characters/pixel_chinchilla.png", mode: "character" },
      paidCharacter("pixel_poop", "똥", "부드러운 코코아색 소용돌이에 반짝이는 눈이 달린 장난꾸러기 친구예요.", "990원"),
      paidCharacter("pixel_capybara", "아기 카피바라", "머리에 귤 하나를 얹고 느긋하게 산책하는 세상 편한 친구예요.", "990원"),
      paidCharacter("pixel_hedgehog", "아기 고슴도치", "뾰족한 가시 아래 크림색 얼굴이 숨어 있는 수줍은 친구예요.", "990원"),
      paidCharacter("pixel_unicorn", "아기 유니콘", "금빛 뿔과 세 가지 색 갈기를 가진 반짝이는 친구예요.", "990원"),
      paidCharacter("pixel_shiba", "아기 시바견", "동그란 눈썹 무늬와 말린 꼬리로 씩씩하게 걷는 친구예요.", "990원"),
      paidCharacter("pixel_salmon_sushi", "연어초밥", "밥 위에 연어 한 점을 얹고 김 띠를 두른 든든한 친구예요.", "990원"),
      paidCharacter("pixel_grandpa", "할아버지", "흰 수염과 동그란 안경, 파란 가디건이 포근한 친구예요.", "990원"),
      paidCharacter("pixel_spider_hero", "거미맨", "빨간 마스크와 큰 흰 눈, 파란 슈트로 화면 가장자리를 지키는 친구예요.", "990원"),
      paidCharacter("pixel_crow", "아기 까마귀", "까만 깃털에 노란 부리, 머리 위 작은 깃 두 개가 귀여운 친구예요.", "990원"),
      paidCharacter("pixel_kimchi", "김치", "새빨간 양념 옷을 입고 초록 배춧잎을 머리에 얹은 매콤한 친구예요.", "990원"),
      paidCharacter("pixel_quokka", "아기 쿼카", "세상에서 가장 행복한 미소로 화면 가장자리를 밝히는 친구예요.", "990원"),
      paidCharacter("pixel_red_panda", "아기 레서판다", "주황 털에 흰 눈썹 무늬, 줄무늬 꼬리를 살랑이는 친구예요.", "990원"),
      paidCharacter("pixel_otter", "아기 수달", "두 손으로 노란 조개를 꼭 안고 다니는 친구예요.", "990원"),
      paidCharacter("pixel_duck", "아기 오리", "노란 솜털에 주황 부리, 머리 위 작은 깃이 귀여운 친구예요.", "990원"),
      paidCharacter("pixel_panda", "아기 판다", "까만 귀와 눈 무늬, 대나무색 목도리를 두른 친구예요.", "990원"),
      paidCharacter("pixel_frog", "아기 개구리", "머리 위로 볼록 솟은 눈과 넓은 미소가 사랑스러운 친구예요.", "990원"),
      paidCharacter("pixel_octopus", "아기 문어", "동글동글한 머리 아래 여덟 다리를 꼬물거리는 친구예요.", "990원"),
      paidCharacter("pixel_bungeoppang", "붕어빵", "노릇한 격자 무늬와 양쪽 지느러미가 살아 있는 겨울 간식 친구예요.", "990원"),
      paidCharacter("pixel_fried_egg", "계란후라이", "하얀 흰자 위에 노른자 얼굴이 톡 올라간 아침 친구예요.", "990원"),
      paidCharacter("pixel_samgak_gimbap", "삼각김밥", "까만 김에 하얀 밥과 빨간 라벨을 두른 삼각형 친구예요.", "990원"),
      paidCharacter("pixel_tteokbokki", "떡볶이", "빨간 양념 위로 떡 세 개가 봉긋 올라온 컵 친구예요.", "990원"),
      paidCharacter("pixel_avocado", "아보카도", "연둣빛 과육 가운데 갈색 씨앗 얼굴이 웃고 있는 친구예요.", "990원"),
      paidCharacter("pixel_slime", "슬라임", "반짝이는 물방울 하이라이트를 품은 말랑한 민트 친구예요.", "990원"),
      paidCharacter("pixel_cactus_pot", "화분", "테라코타 화분 위에서 두 팔 벌린 선인장 친구예요.", "990원"),
      paidCharacter("pixel_tofu", "두부", "파 조각을 얹은 새하얀 네모 두부 친구예요.", "990원"),
      paidCharacter("pixel_cup_ramen", "라면", "김이 모락모락 나는 국물 위에 면과 파를 얹은 야근 친구예요.", "990원"),
      paidCharacter("pixel_grandma", "할머니", "뽀글 파마와 분홍 가디건, 다정한 미소의 친구예요.", "990원"),
      paidCharacter("pixel_baby", "아기", "머리에 곱슬 한 가닥, 쪽쪽이를 문 파란 턱받이 친구예요.", "990원"),
      paidCharacter("pixel_santa", "산타", "빨간 모자와 하얀 수염, 검은 벨트를 맨 선물 배달 친구예요.", "990원"),
      paidCharacter("pixel_jungjiyu", "정지유", "긴 갈색 생머리에 연핑크 가디건과 청바지를 입은 친구예요.", "990원"),
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
      { id: "pixel_guinea_pig", name: "Baby Guinea Pig", description: "Round, cozy, and dressed in warm brown patches.", price: "₩990", asset: "assets/characters/pixel_guinea_pig.png", mode: "character", mirrorsMovement: true },
      { id: "pixel_monkey", name: "Baby Monkey", description: "A bright little walker with chestnut fur and a red scarf.", price: "₩990", asset: "assets/characters/pixel_monkey.png", mode: "character" },
      { id: "pixel_chinchilla", name: "Baby Chinchilla", description: "Big round ears and cloud-soft gray fur in one tiny companion.", price: "₩990", asset: "assets/characters/pixel_chinchilla.png", mode: "character" },
      paidCharacter("pixel_poop", "Poop", "A cheeky cocoa-colored swirl with a pair of sparkling eyes.", "₩990"),
      paidCharacter("pixel_capybara", "Baby Capybara", "A relaxed little friend who strolls with a tangerine on its head.", "₩990"),
      paidCharacter("pixel_hedgehog", "Baby Hedgehog", "A shy cream-colored face peeking out beneath tiny spines.", "₩990"),
      paidCharacter("pixel_unicorn", "Baby Unicorn", "A sparkling friend with a golden horn and a three-color mane.", "₩990"),
      paidCharacter("pixel_shiba", "Baby Shiba", "A spirited pup with round eyebrow markings and a curled tail.", "₩990"),
      paidCharacter("pixel_salmon_sushi", "Salmon Sushi", "A hearty little friend wrapped in nori and topped with salmon.", "₩990"),
      paidCharacter("pixel_grandpa", "Grandpa", "A warm friend in round glasses, a white beard, and a blue cardigan.", "₩990"),
      paidCharacter("pixel_spider_hero", "Spider Hero", "A masked red-and-blue hero watching over the edge of your screen.", "₩990"),
      paidCharacter("pixel_crow", "Baby Crow", "A tiny black bird with a yellow beak and two jaunty head feathers.", "₩990"),
      paidCharacter("pixel_kimchi", "Kimchi", "A spicy red friend topped with crisp green cabbage leaves.", "₩990"),
      paidCharacter("pixel_quokka", "Baby Quokka", "A sunny little friend with an irresistibly happy smile.", "₩990"),
      paidCharacter("pixel_red_panda", "Baby Red Panda", "Orange fur, white brows, and a softly swaying striped tail.", "₩990"),
      paidCharacter("pixel_otter", "Baby Otter", "A gentle otter carrying a yellow shell in both paws.", "₩990"),
      paidCharacter("pixel_duck", "Baby Duck", "Soft yellow down, an orange beak, and one tiny feather on top.", "₩990"),
      paidCharacter("pixel_panda", "Baby Panda", "A bamboo-scarfed friend with round black ears and eye patches.", "₩990"),
      paidCharacter("pixel_frog", "Baby Frog", "A cheerful frog with bright raised eyes and a wonderfully wide smile.", "₩990"),
      paidCharacter("pixel_octopus", "Baby Octopus", "A round little friend who wiggles all eight legs as it walks.", "₩990"),
      paidCharacter("pixel_bungeoppang", "Bungeoppang", "A golden fish-shaped pastry friend with a crisp waffle pattern.", "₩990"),
      paidCharacter("pixel_fried_egg", "Fried Egg", "A bright yolk face perched in the middle of a snowy egg white.", "₩990"),
      paidCharacter("pixel_samgak_gimbap", "Triangle Gimbap", "A triangular rice friend wrapped in dark nori with a red label.", "₩990"),
      paidCharacter("pixel_tteokbokki", "Tteokbokki", "Three rice cakes peeking out of a cup of bright red sauce.", "₩990"),
      paidCharacter("pixel_avocado", "Avocado", "A smiling brown pit nestled in a soft green avocado.", "₩990"),
      paidCharacter("pixel_slime", "Slime", "A minty, squishy friend with a glossy little sparkle.", "₩990"),
      paidCharacter("pixel_cactus_pot", "Potted Cactus", "A tiny cactus stretching both arms from a terracotta pot.", "₩990"),
      paidCharacter("pixel_tofu", "Tofu", "A bright square of tofu topped with a few pieces of scallion.", "₩990"),
      paidCharacter("pixel_cup_ramen", "Ramen", "A cozy bowl of noodles, egg, and scallions with steam rising above.", "₩990"),
      paidCharacter("pixel_grandma", "Grandma", "A kind friend with curly hair, a pink cardigan, and a gentle smile.", "₩990"),
      paidCharacter("pixel_baby", "Baby", "A tiny friend with one curl, a pacifier, and a blue bib.", "₩990"),
      paidCharacter("pixel_santa", "Santa", "A gift-delivering friend in a red hat, white beard, and black belt.", "₩990"),
      paidCharacter("pixel_jungjiyu", "Jung Jiyu", "A friend with long brown hair, a pale pink cardigan, and blue jeans.", "₩990"),
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
      { id: "pixel_guinea_pig", name: "こどもモルモット", description: "ころんとした体と、あたたかな茶色の模様が魅力です。", price: "₩990", asset: "assets/characters/pixel_guinea_pig.png", mode: "character", mirrorsMovement: true },
      { id: "pixel_monkey", name: "こざる", description: "栗色の毛と赤いマフラーで、元気よく歩きます。", price: "₩990", asset: "assets/characters/pixel_monkey.png", mode: "character" },
      { id: "pixel_chinchilla", name: "こどもチンチラ", description: "大きく丸い耳と、雲のようにやわらかな灰色の毛が自慢です。", price: "₩990", asset: "assets/characters/pixel_chinchilla.png", mode: "character" },
      paidCharacter("pixel_poop", "うんち", "ココア色の巻き毛に、きらきらした目を持ついたずら好きです。", "₩990"),
      paidCharacter("pixel_capybara", "こどもカピバラ", "頭にみかんをのせて、のんびり歩くおだやかな友だちです。", "₩990"),
      paidCharacter("pixel_hedgehog", "こどもハリネズミ", "小さな針の下からクリーム色の顔をのぞかせる、恥ずかしがり屋です。", "₩990"),
      paidCharacter("pixel_unicorn", "こどもユニコーン", "金色の角と三色のたてがみが輝く、小さな友だちです。", "₩990"),
      paidCharacter("pixel_shiba", "こども柴犬", "丸いまゆ模様とくるんとしたしっぽで元気に歩きます。", "₩990"),
      paidCharacter("pixel_salmon_sushi", "サーモン寿司", "ご飯にサーモンをのせ、海苔を巻いた頼もしい友だちです。", "₩990"),
      paidCharacter("pixel_grandpa", "おじいさん", "白いひげと丸眼鏡、青いカーディガンが温かな友だちです。", "₩990"),
      paidCharacter("pixel_spider_hero", "スパイダーヒーロー", "赤いマスクと青いスーツで画面の端を見守るヒーローです。", "₩990"),
      paidCharacter("pixel_crow", "こどもカラス", "黒い羽と黄色いくちばし、頭の小さな二本の羽が目印です。", "₩990"),
      paidCharacter("pixel_kimchi", "キムチ", "真っ赤な味付けの服と緑の葉をまとった、ぴりっとした友だちです。", "₩990"),
      paidCharacter("pixel_quokka", "こどもクオッカ", "とびきり幸せそうな笑顔で画面の端を明るくします。", "₩990"),
      paidCharacter("pixel_red_panda", "こどもレッサーパンダ", "橙色の毛と白い眉模様、しましまのしっぽが自慢です。", "₩990"),
      paidCharacter("pixel_otter", "こどもカワウソ", "黄色い貝を両手で大切に抱えて歩く友だちです。", "₩990"),
      paidCharacter("pixel_duck", "こどもアヒル", "黄色い産毛と橙色のくちばし、頭の小さな羽がかわいい友だちです。", "₩990"),
      paidCharacter("pixel_panda", "こどもパンダ", "黒い耳と目の模様に、竹色のマフラーが似合います。", "₩990"),
      paidCharacter("pixel_frog", "こどもカエル", "頭の上の丸い目と、大きな笑顔が愛らしい友だちです。", "₩990"),
      paidCharacter("pixel_octopus", "こどもタコ", "丸い頭の下で八本の足をくねくね動かします。", "₩990"),
      paidCharacter("pixel_bungeoppang", "たい焼き", "こんがりした網目模様とひれを持つ、冬のおやつの友だちです。", "₩990"),
      paidCharacter("pixel_fried_egg", "目玉焼き", "白身の真ん中に、明るい黄身の顔がのった朝の友だちです。", "₩990"),
      paidCharacter("pixel_samgak_gimbap", "三角キンパ", "白いご飯を黒い海苔と赤いラベルで包んだ三角の友だちです。", "₩990"),
      paidCharacter("pixel_tteokbokki", "トッポッキ", "赤いソースのカップから三本のお餅が顔を出しています。", "₩990"),
      paidCharacter("pixel_avocado", "アボカド", "やわらかな緑の果肉で茶色い種の笑顔を包んでいます。", "₩990"),
      paidCharacter("pixel_slime", "スライム", "水滴のきらめきをまとった、ミント色のぷるぷるした友だちです。", "₩990"),
      paidCharacter("pixel_cactus_pot", "サボテン鉢", "テラコッタの鉢から両腕を広げる小さなサボテンです。", "₩990"),
      paidCharacter("pixel_tofu", "豆腐", "ねぎを少しのせた、真っ白で四角い友だちです。", "₩990"),
      paidCharacter("pixel_cup_ramen", "ラーメン", "麺と卵とねぎの上に湯気が立つ、ほっとする友だちです。", "₩990"),
      paidCharacter("pixel_grandma", "おばあさん", "くるくるの髪と桃色のカーディガン、やさしい笑顔が魅力です。", "₩990"),
      paidCharacter("pixel_baby", "あかちゃん", "一本の巻き毛とおしゃぶり、青いよだれかけが目印です。", "₩990"),
      paidCharacter("pixel_santa", "サンタ", "赤い帽子と白いひげ、黒いベルトで贈り物を届けます。", "₩990"),
      paidCharacter("pixel_jungjiyu", "チョン・ジユ", "長い茶色の髪に淡い桃色のカーディガンとジーンズを合わせた友だちです。", "₩990"),
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

export const storeCategoriesByLocale: Record<Locale, StoreCatalog> = { ko, en, ja };
export const storeCategories = ko;

export function getStoreCategories(locale: Locale): StoreCatalog {
  return storeCategoriesByLocale[locale];
}
