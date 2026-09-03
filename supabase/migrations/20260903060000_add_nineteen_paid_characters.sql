begin;

-- Nineteen additional paid characters (2026-09-03, second batch). Production
-- keeps the sales lock; this migration only registers products, prices and the
-- profile ownership contract for the new ids.

insert into public.commerce_products (
  id, display_name, product_description, character_id, entitlement_key, active
)
values
  (
    'character_quokka', '아기 쿼카',
    '세상에서 가장 행복한 미소로 화면 가장자리를 밝히는 친구예요.',
    'pixel_quokka', 'character:pixel_quokka', true
  ),
  (
    'character_red_panda', '아기 레서판다',
    '주황 털에 흰 눈썹 무늬, 줄무늬 꼬리를 살랑이는 친구예요.',
    'pixel_red_panda', 'character:pixel_red_panda', true
  ),
  (
    'character_otter', '아기 수달',
    '두 손으로 노란 조개를 꼭 안고 다니는 친구예요.',
    'pixel_otter', 'character:pixel_otter', true
  ),
  (
    'character_duck', '아기 오리',
    '노란 솜털에 주황 부리, 머리 위 작은 깃이 귀여운 친구예요.',
    'pixel_duck', 'character:pixel_duck', true
  ),
  (
    'character_panda', '아기 판다',
    '까만 귀와 눈 무늬, 대나무색 목도리를 두른 친구예요.',
    'pixel_panda', 'character:pixel_panda', true
  ),
  (
    'character_frog', '아기 개구리',
    '머리 위로 볼록 솟은 눈과 넓은 미소가 사랑스러운 친구예요.',
    'pixel_frog', 'character:pixel_frog', true
  ),
  (
    'character_octopus', '아기 문어',
    '동글동글한 머리 아래 여덟 다리를 꼬물거리는 친구예요.',
    'pixel_octopus', 'character:pixel_octopus', true
  ),
  (
    'character_bungeoppang', '붕어빵',
    '노릇한 격자 무늬와 양쪽 지느러미가 살아 있는 겨울 간식 친구예요.',
    'pixel_bungeoppang', 'character:pixel_bungeoppang', true
  ),
  (
    'character_fried_egg', '계란후라이',
    '하얀 흰자 위에 노른자 얼굴이 톡 올라간 아침 친구예요.',
    'pixel_fried_egg', 'character:pixel_fried_egg', true
  ),
  (
    'character_samgak_gimbap', '삼각김밥',
    '까만 김에 하얀 밥과 빨간 라벨을 두른 삼각형 친구예요.',
    'pixel_samgak_gimbap', 'character:pixel_samgak_gimbap', true
  ),
  (
    'character_tteokbokki', '떡볶이',
    '빨간 양념 위로 떡 세 개가 봉긋 올라온 컵 친구예요.',
    'pixel_tteokbokki', 'character:pixel_tteokbokki', true
  ),
  (
    'character_avocado', '아보카도',
    '연둣빛 과육 가운데 갈색 씨앗 얼굴이 웃고 있는 친구예요.',
    'pixel_avocado', 'character:pixel_avocado', true
  ),
  (
    'character_slime', '슬라임',
    '반짝이는 물방울 하이라이트를 품은 말랑한 민트 친구예요.',
    'pixel_slime', 'character:pixel_slime', true
  ),
  (
    'character_cactus_pot', '화분',
    '테라코타 화분 위에서 두 팔 벌린 선인장 친구예요.',
    'pixel_cactus_pot', 'character:pixel_cactus_pot', true
  ),
  (
    'character_tofu', '두부',
    '파 조각을 얹은 새하얀 네모 두부 친구예요.',
    'pixel_tofu', 'character:pixel_tofu', true
  ),
  (
    'character_cup_ramen', '라면',
    '김이 모락모락 나는 국물 위에 면과 파를 얹은 야근 친구예요.',
    'pixel_cup_ramen', 'character:pixel_cup_ramen', true
  ),
  (
    'character_grandma', '할머니',
    '뽀글 파마와 분홍 가디건, 다정한 미소의 친구예요.',
    'pixel_grandma', 'character:pixel_grandma', true
  ),
  (
    'character_baby', '아기',
    '머리에 곱슬 한 가닥, 쪽쪽이를 문 파란 턱받이 친구예요.',
    'pixel_baby', 'character:pixel_baby', true
  ),
  (
    'character_santa', '산타',
    '빨간 모자와 하얀 수염, 검은 벨트를 맨 선물 배달 친구예요.',
    'pixel_santa', 'character:pixel_santa', true
  )
on conflict (id) do update
set display_name = excluded.display_name,
    product_description = excluded.product_description,
    character_id = excluded.character_id,
    entitlement_key = excluded.entitlement_key,
    active = true,
    updated_at = now();

insert into public.commerce_prices (
  id, product_id, amount_krw, currency, tax_inclusive, active
)
values
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
  ('510e7000-0000-0000-0000-000000001024', 'character_santa', 990, 'KRW', true, true)
on conflict (id) do update
set amount_krw = excluded.amount_krw,
    currency = excluded.currency,
    tax_inclusive = excluded.tax_inclusive,
    active = true,
    retired_at = null;

-- The profile contract lists every selectable character id explicitly. Paid
-- ids still require an active entitlement through the registered product.
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
    'pixel_tofu', 'pixel_cup_ramen', 'pixel_grandma', 'pixel_baby', 'pixel_santa'
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
