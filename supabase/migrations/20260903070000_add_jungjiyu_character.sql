begin;

-- 정지유 (2026-09-03, third batch). Production keeps the sales lock; this
-- migration only registers the product, its price and the profile ownership
-- contract for the new id.

insert into public.commerce_products (
  id, display_name, product_description, character_id, entitlement_key, active
)
values
  (
    'character_jungjiyu', '정지유',
    '앞머리를 내린 긴 갈색 생머리에 흰 이너와 연핑크 가디건, 청바지를 입은 친구예요.',
    'pixel_jungjiyu', 'character:pixel_jungjiyu', true
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
  ('510e7000-0000-0000-0000-000000001025', 'character_jungjiyu', 990, 'KRW', true, true)
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
