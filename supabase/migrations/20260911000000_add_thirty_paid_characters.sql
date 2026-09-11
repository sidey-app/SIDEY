begin;

-- Register the thirty paid characters after the catalog schema gained
-- product_kind, catalog_item_id, and sort_order. Keeping this as a forward-only
-- migration makes it safe for both fresh databases and databases already on the
-- 20260905 cosmetics catalog schema.
insert into public.commerce_products (
  id, display_name, product_description, character_id, entitlement_key,
  product_kind, catalog_item_id, sort_order, active
)
values
  ('character_poop', '똥', '부드러운 코코아색 소용돌이에 반짝이는 눈이 달린 장난꾸러기 친구예요.',
   'pixel_poop', 'character:pixel_poop', 'character', 'pixel_poop', 90, true),
  ('character_capybara', '아기 카피바라', '머리에 귤 하나를 얹고 느긋하게 산책하는 세상 편한 친구예요.',
   'pixel_capybara', 'character:pixel_capybara', 'character', 'pixel_capybara', 90, true),
  ('character_hedgehog', '아기 고슴도치', '뾰족한 가시 아래 크림색 얼굴이 숨어 있는 수줍은 친구예요.',
   'pixel_hedgehog', 'character:pixel_hedgehog', 'character', 'pixel_hedgehog', 90, true),
  ('character_unicorn', '아기 유니콘', '금빛 뿔과 세 가지 색 갈기를 가진 반짝이는 친구예요.',
   'pixel_unicorn', 'character:pixel_unicorn', 'character', 'pixel_unicorn', 90, true),
  ('character_shiba', '아기 시바견', '동그란 눈썹 무늬와 말린 꼬리로 씩씩하게 걷는 친구예요.',
   'pixel_shiba', 'character:pixel_shiba', 'character', 'pixel_shiba', 90, true),
  ('character_salmon_sushi', '연어초밥', '밥 위에 연어 한 점을 얹고 김 띠를 두른 든든한 친구예요.',
   'pixel_salmon_sushi', 'character:pixel_salmon_sushi', 'character', 'pixel_salmon_sushi', 90, true),
  ('character_grandpa', '할아버지', '흰 수염과 동그란 안경, 파란 가디건이 포근한 친구예요.',
   'pixel_grandpa', 'character:pixel_grandpa', 'character', 'pixel_grandpa', 90, true),
  ('character_spider_hero', '거미맨', '빨간 마스크와 큰 흰 눈, 파란 슈트로 화면 가장자리를 지키는 친구예요.',
   'pixel_spider_hero', 'character:pixel_spider_hero', 'character', 'pixel_spider_hero', 90, true),
  ('character_crow', '아기 까마귀', '까만 깃털에 노란 부리, 머리 위 작은 깃 두 개가 귀여운 친구예요.',
   'pixel_crow', 'character:pixel_crow', 'character', 'pixel_crow', 90, true),
  ('character_kimchi', '김치', '새빨간 양념 옷을 입고 초록 배춧잎을 머리에 얹은 매콤한 친구예요.',
   'pixel_kimchi', 'character:pixel_kimchi', 'character', 'pixel_kimchi', 90, true),
  ('character_quokka', '아기 쿼카', '세상에서 가장 행복한 미소로 화면 가장자리를 밝히는 친구예요.',
   'pixel_quokka', 'character:pixel_quokka', 'character', 'pixel_quokka', 90, true),
  ('character_red_panda', '아기 레서판다', '주황 털에 흰 눈썹 무늬, 줄무늬 꼬리를 살랑이는 친구예요.',
   'pixel_red_panda', 'character:pixel_red_panda', 'character', 'pixel_red_panda', 90, true),
  ('character_otter', '아기 수달', '두 손으로 노란 조개를 꼭 안고 다니는 친구예요.',
   'pixel_otter', 'character:pixel_otter', 'character', 'pixel_otter', 90, true),
  ('character_duck', '아기 오리', '노란 솜털에 주황 부리, 머리 위 작은 깃이 귀여운 친구예요.',
   'pixel_duck', 'character:pixel_duck', 'character', 'pixel_duck', 90, true),
  ('character_panda', '아기 판다', '까만 귀와 눈 무늬, 대나무색 목도리를 두른 친구예요.',
   'pixel_panda', 'character:pixel_panda', 'character', 'pixel_panda', 90, true),
  ('character_frog', '아기 개구리', '머리 위로 볼록 솟은 눈과 넓은 미소가 사랑스러운 친구예요.',
   'pixel_frog', 'character:pixel_frog', 'character', 'pixel_frog', 90, true),
  ('character_octopus', '아기 문어', '동글동글한 머리 아래 여덟 다리를 꼬물거리는 친구예요.',
   'pixel_octopus', 'character:pixel_octopus', 'character', 'pixel_octopus', 90, true),
  ('character_bungeoppang', '붕어빵', '노릇한 격자 무늬와 양쪽 지느러미가 살아 있는 겨울 간식 친구예요.',
   'pixel_bungeoppang', 'character:pixel_bungeoppang', 'character', 'pixel_bungeoppang', 90, true),
  ('character_fried_egg', '계란후라이', '하얀 흰자 위에 노른자 얼굴이 톡 올라간 아침 친구예요.',
   'pixel_fried_egg', 'character:pixel_fried_egg', 'character', 'pixel_fried_egg', 90, true),
  ('character_samgak_gimbap', '삼각김밥', '까만 김에 하얀 밥과 빨간 라벨을 두른 삼각형 친구예요.',
   'pixel_samgak_gimbap', 'character:pixel_samgak_gimbap', 'character', 'pixel_samgak_gimbap', 90, true),
  ('character_tteokbokki', '떡볶이', '빨간 양념 위로 떡 세 개가 봉긋 올라온 컵 친구예요.',
   'pixel_tteokbokki', 'character:pixel_tteokbokki', 'character', 'pixel_tteokbokki', 90, true),
  ('character_avocado', '아보카도', '연둣빛 과육 가운데 갈색 씨앗 얼굴이 웃고 있는 친구예요.',
   'pixel_avocado', 'character:pixel_avocado', 'character', 'pixel_avocado', 90, true),
  ('character_slime', '슬라임', '반짝이는 물방울 하이라이트를 품은 말랑한 민트 친구예요.',
   'pixel_slime', 'character:pixel_slime', 'character', 'pixel_slime', 90, true),
  ('character_cactus_pot', '화분', '테라코타 화분 위에서 두 팔 벌린 선인장 친구예요.',
   'pixel_cactus_pot', 'character:pixel_cactus_pot', 'character', 'pixel_cactus_pot', 90, true),
  ('character_tofu', '두부', '파 조각을 얹은 새하얀 네모 두부 친구예요.',
   'pixel_tofu', 'character:pixel_tofu', 'character', 'pixel_tofu', 90, true),
  ('character_cup_ramen', '라면', '김이 모락모락 나는 국물 위에 면과 파를 얹은 야근 친구예요.',
   'pixel_cup_ramen', 'character:pixel_cup_ramen', 'character', 'pixel_cup_ramen', 90, true),
  ('character_grandma', '할머니', '뽀글 파마와 분홍 가디건, 다정한 미소의 친구예요.',
   'pixel_grandma', 'character:pixel_grandma', 'character', 'pixel_grandma', 90, true),
  ('character_baby', '아기', '머리에 곱슬 한 가닥, 쪽쪽이를 문 파란 턱받이 친구예요.',
   'pixel_baby', 'character:pixel_baby', 'character', 'pixel_baby', 90, true),
  ('character_santa', '산타', '빨간 모자와 하얀 수염, 검은 벨트를 맨 선물 배달 친구예요.',
   'pixel_santa', 'character:pixel_santa', 'character', 'pixel_santa', 90, true),
  ('character_jungjiyu', '정지유', '앞머리를 내린 긴 갈색 생머리에 흰 이너와 연핑크 가디건, 청바지를 입은 친구예요.',
   'pixel_jungjiyu', 'character:pixel_jungjiyu', 'character', 'pixel_jungjiyu', 90, true)
on conflict (id) do update
set display_name = excluded.display_name,
    product_description = excluded.product_description,
    character_id = excluded.character_id,
    entitlement_key = excluded.entitlement_key,
    product_kind = excluded.product_kind,
    catalog_item_id = excluded.catalog_item_id,
    sort_order = excluded.sort_order,
    active = true,
    updated_at = now();

insert into public.commerce_prices (
  id, product_id, amount_krw, currency, tax_inclusive, active
)
values
  ('510e7000-0000-0000-0000-000000000994', 'character_poop', 990, 'KRW', true, true),
  ('510e7000-0000-0000-0000-000000000995', 'character_capybara', 990, 'KRW', true, true),
  ('510e7000-0000-0000-0000-000000000996', 'character_hedgehog', 990, 'KRW', true, true),
  ('510e7000-0000-0000-0000-000000000997', 'character_unicorn', 990, 'KRW', true, true),
  ('510e7000-0000-0000-0000-000000000998', 'character_shiba', 990, 'KRW', true, true),
  ('510e7000-0000-0000-0000-000000000999', 'character_salmon_sushi', 990, 'KRW', true, true),
  ('510e7000-0000-0000-0000-000000001000', 'character_grandpa', 990, 'KRW', true, true),
  ('510e7000-0000-0000-0000-000000001001', 'character_spider_hero', 990, 'KRW', true, true),
  ('510e7000-0000-0000-0000-000000001002', 'character_crow', 990, 'KRW', true, true),
  ('510e7000-0000-0000-0000-000000001003', 'character_kimchi', 990, 'KRW', true, true),
  ('510e7000-0000-0000-0000-000000001004', 'character_quokka', 990, 'KRW', true, true),
  ('510e7000-0000-0000-0000-000000001005', 'character_red_panda', 990, 'KRW', true, true),
  ('510e7000-0000-0000-0000-000000001007', 'character_otter', 990, 'KRW', true, true),
  ('510e7000-0000-0000-0000-000000001008', 'character_duck', 990, 'KRW', true, true),
  ('510e7000-0000-0000-0000-000000001009', 'character_panda', 990, 'KRW', true, true),
  ('510e7000-0000-0000-0000-000000001010', 'character_frog', 990, 'KRW', true, true),
  ('510e7000-0000-0000-0000-000000001011', 'character_octopus', 990, 'KRW', true, true),
  ('510e7000-0000-0000-0000-000000001012', 'character_bungeoppang', 990, 'KRW', true, true),
  ('510e7000-0000-0000-0000-000000001013', 'character_fried_egg', 990, 'KRW', true, true),
  ('510e7000-0000-0000-0000-000000001014', 'character_samgak_gimbap', 990, 'KRW', true, true),
  ('510e7000-0000-0000-0000-000000001015', 'character_tteokbokki', 990, 'KRW', true, true),
  ('510e7000-0000-0000-0000-000000001016', 'character_avocado', 990, 'KRW', true, true),
  ('510e7000-0000-0000-0000-000000001018', 'character_slime', 990, 'KRW', true, true),
  ('510e7000-0000-0000-0000-000000001019', 'character_cactus_pot', 990, 'KRW', true, true),
  ('510e7000-0000-0000-0000-000000001020', 'character_tofu', 990, 'KRW', true, true),
  ('510e7000-0000-0000-0000-000000001021', 'character_cup_ramen', 990, 'KRW', true, true),
  ('510e7000-0000-0000-0000-000000001022', 'character_grandma', 990, 'KRW', true, true),
  ('510e7000-0000-0000-0000-000000001023', 'character_baby', 990, 'KRW', true, true),
  ('510e7000-0000-0000-0000-000000001024', 'character_santa', 990, 'KRW', true, true),
  ('510e7000-0000-0000-0000-000000001025', 'character_jungjiyu', 990, 'KRW', true, true)
on conflict (id) do update
set product_id = excluded.product_id,
    amount_krw = excluded.amount_krw,
    currency = excluded.currency,
    tax_inclusive = excluded.tax_inclusive,
    active = true,
    retired_at = null;

-- Extend the profile contract without replacing any of the newer commerce or
-- cosmetic functions introduced before this migration.
create or replace function public.upsert_profile(
  p_nickname text,
  p_character_id text default 'pixel_hamster'
)
returns public.profiles
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  normalized_character_id text := case
    when p_character_id = 'minty_pup' then 'pixel_hamster'
    when p_character_id = 'pixel_koala' then 'pixel_chinchilla'
    else p_character_id
  end;
  required_entitlement text;
  saved_profile public.profiles;
begin
  if current_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if char_length(btrim(p_nickname)) not between 2 and 8
     or p_nickname ~ E'[\n\r\t]' then
    raise exception using errcode = '22023', message = 'invalid_nickname';
  end if;
  if normalized_character_id not in (
    'pixel_hamster', 'pixel_cat', 'pixel_puppy', 'pixel_rabbit', 'pixel_penguin',
    'pixel_guinea_pig', 'pixel_monkey', 'pixel_chinchilla', 'pixel_starlight_upalupa', 'pixel_poop',
    'pixel_capybara', 'pixel_hedgehog', 'pixel_unicorn', 'pixel_shiba', 'pixel_salmon_sushi',
    'pixel_grandpa', 'pixel_spider_hero', 'pixel_crow', 'pixel_kimchi', 'pixel_quokka',
    'pixel_red_panda', 'pixel_otter', 'pixel_duck', 'pixel_panda',
    'pixel_frog', 'pixel_octopus', 'pixel_bungeoppang', 'pixel_fried_egg', 'pixel_samgak_gimbap',
    'pixel_tteokbokki', 'pixel_avocado', 'pixel_slime', 'pixel_cactus_pot',
    'pixel_tofu', 'pixel_cup_ramen', 'pixel_grandma', 'pixel_baby', 'pixel_santa',
    'pixel_jungjiyu'
  ) then
    raise exception using errcode = '22023', message = 'invalid_character_id';
  end if;

  select products.entitlement_key into required_entitlement
  from public.commerce_products products
  where products.character_id = normalized_character_id
    and products.active is true;

  if required_entitlement is not null and not exists (
    select 1 from public.commerce_entitlements entitlements
    where entitlements.user_id = current_user_id
      and entitlements.entitlement_key = required_entitlement
      and entitlements.status = 'active'
  ) then
    raise exception using errcode = '42501', message = 'character_ownership_required';
  end if;

  insert into public.profiles (id, nickname, character_id)
  values (current_user_id, btrim(p_nickname), normalized_character_id)
  on conflict (id) do update
  set nickname = excluded.nickname,
      character_id = excluded.character_id,
      updated_at = now()
  returning * into saved_profile;
  return saved_profile;
end;
$$;

revoke all on function public.upsert_profile(text, text) from public, anon;
grant execute on function public.upsert_profile(text, text) to authenticated;

commit;
