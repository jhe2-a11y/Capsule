-- Storage layer hardening:
--   1. Tighten capsule_id_from_path so it only matches real UUID
--      hex layout (not any 36-char hex/dash string), and wrap the
--      cast so a malformed path returns NULL instead of raising
--      `invalid input syntax for type uuid` (which becomes HTTP 500).
--   2. Belt-and-braces: enable RLS on storage.objects. Real Supabase
--      already has this on by default, but our CI Postgres stub
--      doesn't — the migration was silently no-op'ing in CI.

create or replace function storage.capsule_id_from_path(p_name text)
returns uuid
language plpgsql
immutable
as $$
declare
  prefix text;
begin
  if p_name !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/' then
    return null;
  end if;
  prefix := split_part(p_name, '/', 1);
  return prefix::uuid;
exception
  when invalid_text_representation then
    return null;
end;
$$;

-- Idempotent: noop on real Supabase, materially correct in CI.
alter table storage.objects enable row level security;
