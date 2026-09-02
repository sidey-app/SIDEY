begin;

set local role postgres;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(57);

select has_table('public', 'commerce_products', 'commerce products are public catalog data');
select has_table('public', 'commerce_prices', 'commerce prices are server catalog data');
select has_table('public', 'commerce_orders', 'commerce orders exist');
select has_table('public', 'commerce_entitlements', 'commerce entitlements exist');
select has_table('private', 'commerce_payments', 'provider payment identifiers stay private');
select has_table('private', 'commerce_webhook_events', 'webhook idempotency records stay private');
select has_table('private', 'commerce_runtime_settings', 'sales lock and current policy stay private');
select has_table('private', 'commerce_refund_operations', 'refund operations have a private audit trail');
select is(
  (select sales_enabled from private.commerce_runtime_settings where singleton),
  false,
  'forward migration keeps live sales locked by default'
);
select has_column('public', 'commerce_orders', 'policy_version', 'orders store the accepted policy version');
select has_column('public', 'commerce_orders', 'policy_notice', 'orders store the checkout disclosure verbatim');
select has_column('public', 'commerce_orders', 'policy_consented_at', 'orders store the explicit consent time');
select is(
  (select amount_krw from public.commerce_prices where product_id = 'character_starlight_upalupa' and active),
  990,
  'active server price is 990 KRW'
);
select ok(
  (select tax_inclusive from public.commerce_prices where product_id = 'character_starlight_upalupa' and active),
  'active price includes VAT'
);
select results_eq(
  $$select character_id, entitlement_key from public.commerce_products
    where id = 'character_starlight_upalupa'$$,
  $$values ('pixel_starlight_upalupa'::text, 'character:pixel_starlight_upalupa'::text)$$,
  'product, character, and entitlement identifiers are fixed'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.commerce_orders'::regclass),
  'orders have RLS enabled'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.commerce_entitlements'::regclass),
  'entitlements have RLS enabled'
);
select ok(
  not has_table_privilege('authenticated', 'public.commerce_orders', 'insert'),
  'clients cannot create orders by writing tables'
);
select ok(
  has_function_privilege('service_role', 'public.commerce_cancel_checkout(text)', 'execute')
    and not has_function_privilege('authenticated', 'public.commerce_cancel_checkout(text)', 'execute'),
  'only the service role can cancel a pending checkout token'
);
select ok(
  not has_function_privilege('service_role', 'public.commerce_refund_target(uuid)', 'execute')
    and has_function_privilege(
      'service_role',
      'public.commerce_refund_target(uuid,text,uuid,text,text)',
      'execute'
    ),
  'the service role can use only the reasoned refund target function'
);

insert into auth.users (
  id, instance_id, aud, role, raw_app_meta_data, raw_user_meta_data,
  is_anonymous, created_at, updated_at
)
values
  ('20000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', '{"provider":"anonymous","providers":["anonymous"]}', '{}', true, now(), now()),
  ('20000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', '{"provider":"anonymous","providers":["anonymous"]}', '{}', true, now(), now());

select set_config('request.jwt.claim.sub', '20000000-0000-0000-0000-000000000001', true);
select public.upsert_profile('별빛친구', 'pixel_hamster');

select is(
  (select google_connected from public.get_commerce_state()),
  false,
  'anonymous account initially needs Google linking'
);
select throws_ok(
  $$select public.upsert_profile('별빛친구', 'pixel_starlight_upalupa')$$,
  '42501',
  'character_ownership_required',
  'paid character selection is rejected without ownership'
);
select throws_ok(
  $$select * from public.create_commerce_order(
      'character_starlight_upalupa', repeat('a', 64)
    )$$,
  'P0001',
  'google_identity_required',
  'checkout creation requires a linked Google identity'
);

update auth.users
set raw_app_meta_data = '{"provider":"google","providers":["anonymous","google"]}',
    is_anonymous = false
where id = '20000000-0000-0000-0000-000000000001';

select is(
  (select google_connected from public.get_commerce_state()),
  true,
  'linked Google identity is reflected in commerce state'
);

select throws_ok(
  $$select * from public.create_commerce_order(
      'character_starlight_upalupa', repeat('c', 64)
    )$$,
  'P0001',
  'commerce_sales_disabled',
  'new orders stay blocked while the server sales switch is off'
);

update private.commerce_runtime_settings
set sales_enabled = true,
    updated_at = now()
where singleton is true;

create temporary table commerce_test_order as
select * from public.create_commerce_order(
  'character_starlight_upalupa',
  '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
);
grant select on commerce_test_order to authenticated;

select is((select amount_krw from commerce_test_order), 990, 'order copies the active server price');
select is((select currency from commerce_test_order), 'KRW', 'order copies the server currency');
select is(
  (select octet_length(checkout_token_hash) from public.commerce_orders
   where id = (select order_id from commerce_test_order)),
  32,
  'only a 256-bit checkout token hash is stored'
);
select is(
  (select policy_consented_at is null from public.commerce_orders
   where id = (select order_id from commerce_test_order)),
  true,
  'a prepared order does not imply policy consent'
);
select is(
  (select policy_version from public.commerce_checkout_prepare(
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
  )),
  '2026-09-02-v2',
  'checkout preparation returns the canonical current policy'
);
select is(
  (select count(*)::integer from public.commerce_checkout_order(
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
  )),
  0,
  'payment configuration is hidden before consent'
);
select throws_ok(
  format(
    $$select public.commerce_record_approval(%L, 'test_payment_key_000001', 990, 'KRW', null, now())$$,
    (select provider_order_id from commerce_test_order)
  ),
  '42501',
  'payment_policy_consent_required',
  'approval cannot grant ownership without checkout consent'
);
select throws_ok(
  $$select * from public.commerce_record_policy_consent(
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
    'stale-policy'
  )$$,
  '22023',
  'commerce_policy_version_mismatch',
  'stale policy versions cannot be accepted'
);

create temporary table commerce_test_consent as
select * from public.commerce_record_policy_consent(
  '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
  '2026-09-02-v2'
);

select is(
  (select policy_version from commerce_test_consent),
  '2026-09-02-v2',
  'explicit consent records the policy version'
);
select is(
  (select policy_consented_at from public.commerce_record_policy_consent(
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
    '2026-09-02-v2'
  )),
  (select policy_consented_at from commerce_test_consent),
  'duplicate consent is idempotent and preserves its first timestamp'
);
select is(
  (select count(*)::integer from public.commerce_checkout_order(
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
  )),
  1,
  'payment configuration is available after consent'
);
select is(
  (select policy_notice from public.commerce_orders
   where id = (select order_id from commerce_test_order)),
  (select policy_notice from private.commerce_runtime_settings where singleton),
  'the exact server disclosure is copied into the order'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '20000000-0000-0000-0000-000000000001', true);
select is(
  (select count(*)::integer from public.commerce_orders),
  1,
  'buyer can read the buyer order'
);
select set_config('request.jwt.claim.sub', '20000000-0000-0000-0000-000000000002', true);
select is(
  (select count(*)::integer from public.commerce_orders),
  0,
  'another user cannot read the buyer order'
);

set local role postgres;
select is(
  public.commerce_record_approval(
    (select provider_order_id from commerce_test_order),
    'test_payment_key_000001',
    990,
    'KRW',
    'test_transaction_000001',
    now()
  ),
  'approved',
  'verified approval marks the order approved'
);
select is(
  (select status from public.commerce_entitlements
   where user_id = '20000000-0000-0000-0000-000000000001'
     and entitlement_key = 'character:pixel_starlight_upalupa'),
  'active',
  'approval grants an active account entitlement'
);
select lives_ok(
  $$select public.commerce_record_approval(
      (select provider_order_id from commerce_test_order),
      'test_payment_key_000001', 990, 'KRW', 'test_transaction_000001', now()
    )$$,
  'duplicate approval is idempotent'
);
select set_config('request.jwt.claim.sub', '20000000-0000-0000-0000-000000000001', true);
select lives_ok(
  $$select public.upsert_profile('별빛친구', 'pixel_starlight_upalupa')$$,
  'owned paid character can be selected'
);
select is(
  (select character_id from public.profiles where id = '20000000-0000-0000-0000-000000000001'),
  'pixel_starlight_upalupa',
  'owned character is stored on the profile'
);
select throws_ok(
  format(
    $$select public.commerce_record_approval(%L, 'test_payment_key_000001', 991, 'KRW', null, now())$$,
    (select provider_order_id from commerce_test_order)
  ),
  '22023',
  'commerce_amount_mismatch',
  'provider amount mismatches are rejected'
);
select throws_ok(
  format(
    $$select * from public.commerce_refund_target(%L::uuid)$$,
    (select order_id from commerce_test_order)
  ),
  '22023',
  'refund_reason_required',
  'the legacy reasonless refund lookup is disabled'
);
select throws_ok(
  format(
    $$select * from public.commerce_refund_target(
      %L::uuid, 'simple_change_of_mind',
      '30000000-0000-4000-8000-000000000001'::uuid,
      'ops-test', null
    )$$,
    (select order_id from commerce_test_order)
  ),
  '22023',
  'invalid_refund_reason',
  'simple change of mind is not an allowed operations refund reason'
);
select is(
  (select count(*)::integer from public.commerce_refund_target(
    (select order_id from commerce_test_order),
    'contract_mismatch',
    '30000000-0000-4000-8000-000000000001',
    'ops-test',
    'fixture contract mismatch'
  )),
  1,
  'an approved order is eligible with an allowed statutory reason'
);
select results_eq(
  $$select reason_code, processing_status
    from private.commerce_refund_operations
    where order_id = (select order_id from commerce_test_order)$$,
  $$values ('contract_mismatch'::text, 'requested'::text)$$,
  'refund reason and request state are recorded privately'
);

select is(
  public.commerce_record_provider_state(
    'refund-event-1',
    'SIDEY_REFUND',
    repeat('b', 64),
    (select provider_order_id from commerce_test_order),
    'test_payment_key_000001',
    990,
    0,
    'KRW',
    'CANCELED',
    'test_refund_transaction_000001',
    now()
  ),
  'refunded',
  'verified full cancellation marks the order refunded'
);
select lives_ok(
  $$select public.commerce_record_refund_result(
    (select order_id from commerce_test_order),
    'completed',
    'refund_verified',
    'CANCELED'
  )$$,
  'verified refund result can be recorded'
);
select results_eq(
  $$select processing_status, result_code, provider_status
    from private.commerce_refund_operations
    where order_id = (select order_id from commerce_test_order)$$,
  $$values ('completed'::text, 'refund_verified'::text, 'CANCELED'::text)$$,
  'private refund audit stores the final processing result'
);
select is(
  (select status from public.commerce_entitlements
   where user_id = '20000000-0000-0000-0000-000000000001'
     and entitlement_key = 'character:pixel_starlight_upalupa'),
  'refunded',
  'refund revokes the paid entitlement'
);
select is(
  (select character_id from public.profiles where id = '20000000-0000-0000-0000-000000000001'),
  'pixel_hamster',
  'refund returns an active paid profile to the default hamster'
);
select is(
  public.commerce_record_provider_state(
    'refund-event-1',
    'SIDEY_REFUND',
    repeat('b', 64),
    (select provider_order_id from commerce_test_order),
    'test_payment_key_000001',
    990,
    0,
    'KRW',
    'CANCELED',
    'test_refund_transaction_000001',
    now()
  ),
  'refunded',
  'duplicate refund event is idempotent'
);
select is(
  (select count(*)::integer from public.commerce_refund_target(
    (select order_id from commerce_test_order),
    'contract_mismatch',
    '30000000-0000-4000-8000-000000000001',
    'ops-test',
    'fixture contract mismatch'
  )),
  0,
  'refunded order cannot be refunded twice'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '20000000-0000-0000-0000-000000000002', true);
select is(
  (select count(*)::integer from public.commerce_entitlements),
  0,
  'another user cannot read the buyer entitlement'
);

select * from finish();
rollback;
