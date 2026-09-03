begin;

-- Ten additional paid characters. Production keeps the sales lock from
-- 20260902050000_paid_characters_portone_v2.sql; this migration only registers
-- products, prices and the profile ownership contract for the new ids.

insert into public.commerce_products (
  id, display_name, product_description, character_id, entitlement_key, active
)
values
  (
    'character_poop', '똥',
    '부드러운 코코아색 소용돌이에 반짝이는 눈이 달린 장난꾸러기 친구예요.',
    'pixel_poop', 'character:pixel_poop', true
  ),
  (
    'character_capybara', '아기 카피바라',
    '머리에 귤 하나를 얹고 느긋하게 산책하는 세상 편한 친구예요.',
    'pixel_capybara', 'character:pixel_capybara', true
  ),
  (
    'character_hedgehog', '아기 고슴도치',
    '뾰족한 가시 아래 크림색 얼굴이 숨어 있는 수줍은 친구예요.',
    'pixel_hedgehog', 'character:pixel_hedgehog', true
  ),
  (
    'character_unicorn', '아기 유니콘',
    '금빛 뿔과 세 가지 색 갈기를 가진 반짝이는 친구예요.',
    'pixel_unicorn', 'character:pixel_unicorn', true
  ),
  (
    'character_shiba', '아기 시바견',
    '동그란 눈썹 무늬와 말린 꼬리로 씩씩하게 걷는 친구예요.',
    'pixel_shiba', 'character:pixel_shiba', true
  ),
  (
    'character_salmon_sushi', '연어초밥',
    '밥 위에 연어 한 점을 얹고 김 띠를 두른 든든한 친구예요.',
    'pixel_salmon_sushi', 'character:pixel_salmon_sushi', true
  ),
  (
    'character_grandpa', '할아버지',
    '흰 수염과 동그란 안경, 파란 가디건이 포근한 친구예요.',
    'pixel_grandpa', 'character:pixel_grandpa', true
  ),
  (
    'character_spider_hero', '거미맨',
    '빨간 마스크와 큰 흰 눈, 파란 슈트로 화면 가장자리를 지키는 친구예요.',
    'pixel_spider_hero', 'character:pixel_spider_hero', true
  ),
  (
    'character_crow', '아기 까마귀',
    '까만 깃털에 노란 부리, 머리 위 작은 깃 두 개가 귀여운 친구예요.',
    'pixel_crow', 'character:pixel_crow', true
  ),
  (
    'character_kimchi', '김치',
    '새빨간 양념 옷을 입고 초록 배춧잎을 머리에 얹은 매콤한 친구예요.',
    'pixel_kimchi', 'character:pixel_kimchi', true
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
  ('510e7000-0000-0000-0000-000000000994', 'character_poop', 990, 'KRW', true, true),
  ('510e7000-0000-0000-0000-000000000995', 'character_capybara', 990, 'KRW', true, true),
  ('510e7000-0000-0000-0000-000000000996', 'character_hedgehog', 990, 'KRW', true, true),
  ('510e7000-0000-0000-0000-000000000997', 'character_unicorn', 990, 'KRW', true, true),
  ('510e7000-0000-0000-0000-000000000998', 'character_shiba', 990, 'KRW', true, true),
  ('510e7000-0000-0000-0000-000000000999', 'character_salmon_sushi', 990, 'KRW', true, true),
  ('510e7000-0000-0000-0000-000000001000', 'character_grandpa', 990, 'KRW', true, true),
  ('510e7000-0000-0000-0000-000000001001', 'character_spider_hero', 990, 'KRW', true, true),
  ('510e7000-0000-0000-0000-000000001002', 'character_crow', 990, 'KRW', true, true),
  ('510e7000-0000-0000-0000-000000001003', 'character_kimchi', 990, 'KRW', true, true)
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
    'pixel_guinea_pig', 'pixel_monkey', 'pixel_chinchilla',
    'pixel_starlight_upalupa',
    'pixel_poop', 'pixel_capybara', 'pixel_hedgehog', 'pixel_unicorn', 'pixel_shiba',
    'pixel_salmon_sushi', 'pixel_grandpa', 'pixel_spider_hero', 'pixel_crow', 'pixel_kimchi'
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
