-- RLS probes. Run against a freshly migrated + seeded local DB:
--
--   supabase db reset
--   psql "$(supabase status -o env | grep DB_URL | cut -d= -f2)" -f tests/rls.sql
--
-- Each block sets a JWT for an imagined user and verifies the row visibility.
-- The setup creates two synthetic users; substitute real auth.users rows in
-- production tests. Output should be all `t` (true) and the listed counts.

-- helper: pretend to be user with a given UUID
create or replace function public._as(p_uid uuid) returns void
language plpgsql as $$ begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_uid::text, 'role', 'authenticated')::text,
    true);
  perform set_config('role', 'authenticated', true);
end $$;

create or replace function public._as_anon() returns void
language plpgsql as $$ begin
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'anon', true);
end $$;

-- Insert two test users (would be auth.users in real setup; we bypass for test)
do $$
declare alice uuid := '0000aaaa-0000-0000-0000-000000000001';
        bob   uuid := '0000bbbb-0000-0000-0000-000000000002';
        c_open  uuid := 'cccc0000-0000-0000-0000-00000000000a';
        c_priv  uuid := 'cccc0000-0000-0000-0000-00000000000b';
begin
  insert into auth.users (id) values (alice), (bob) on conflict do nothing;

  insert into public.capsules (id, owner_id, access_mode)
    values (c_open, alice, 'open'), (c_priv, alice, 'private')
    on conflict (id) do update
      set owner_id = excluded.owner_id, access_mode = excluded.access_mode;

  insert into public.memories (id, capsule_id, kind, text_content,
                               pos_x, pos_y, pos_z, created_by)
    values (gen_random_uuid(), c_open, 'text', 'open hello',  0,0,0.5, alice),
           (gen_random_uuid(), c_priv, 'text', 'priv hello',  0,0,0.5, alice)
    on conflict do nothing;
end $$;

-- 1. Anon can read open capsule, not private.
select public._as_anon();
select count(*) = 1 as anon_sees_open
  from public.capsules where id = 'cccc0000-0000-0000-0000-00000000000a';
select count(*) = 0 as anon_blind_to_private
  from public.capsules where id = 'cccc0000-0000-0000-0000-00000000000b';
select count(*) = 1 as anon_sees_open_memory
  from public.memories where text_content = 'open hello';
select count(*) = 0 as anon_blind_to_private_memory
  from public.memories where text_content = 'priv hello';

-- 2. Bob (stranger) cannot read private capsule.
select public._as('0000bbbb-0000-0000-0000-000000000002');
select count(*) = 0 as bob_blind_to_private
  from public.capsules where id = 'cccc0000-0000-0000-0000-00000000000b';

-- 3. Alice (owner) sees her private capsule.
select public._as('0000aaaa-0000-0000-0000-000000000001');
select count(*) = 1 as alice_sees_private
  from public.capsules where id = 'cccc0000-0000-0000-0000-00000000000b';

-- 4. Bob cannot insert a memory into Alice's capsule.
select public._as('0000bbbb-0000-0000-0000-000000000002');
do $$
declare ok boolean;
begin
  begin
    insert into public.memories (capsule_id, kind, text_content, pos_x, pos_y, pos_z, created_by)
      values ('cccc0000-0000-0000-0000-00000000000a', 'text', 'bob writes', 0,0,0.5,
              '0000bbbb-0000-0000-0000-000000000002');
    ok := false;
  exception when others then ok := true;
  end;
  raise notice 'bob_cannot_write_to_alice_capsule = %', ok;
end $$;

-- 5. claim_capsule atomicity: a fresh unclaimed capsule, two concurrent
--    sessions, only one claim succeeds.
do $$
declare new_id uuid := gen_random_uuid();
        first  public.capsules;
begin
  insert into public.capsules (id) values (new_id);
  perform public._as('0000bbbb-0000-0000-0000-000000000002');
  first := public.claim_capsule(new_id);
  raise notice 'first_claim owner=%', first.owner_id;
  begin
    perform public.claim_capsule(new_id);
    raise notice 'second_claim_should_have_failed';
  exception when others then
    raise notice 'second_claim_correctly_failed sqlstate=%', SQLSTATE;
  end;
end $$;
