-- Pre-seed a small batch of unclaimed capsules. In production this is the
-- output of the manufacturing pipeline; the printed UUID on the chip matches
-- a row here. For local dev we hardcode a few well-known IDs.

insert into public.capsules (id, access_mode, title) values
  ('11111111-1111-1111-1111-111111111111', 'open',    null),
  ('22222222-2222-2222-2222-222222222222', 'open',    null),
  ('33333333-3333-3333-3333-333333333333', 'private', null),
  ('44444444-4444-4444-4444-444444444444', 'open',    null),
  ('55555555-5555-5555-5555-555555555555', 'open',    null)
on conflict (id) do nothing;
