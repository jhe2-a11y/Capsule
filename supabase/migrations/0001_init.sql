-- Capsule: initial schema, RLS policies, and atomic claim RPC.
-- A row in `capsules` is pre-seeded by the manufacturing pipeline before the
-- physical chip is shipped; the chip's NDEF Universal Link encodes the row's
-- UUID. Ownership is established by the first authenticated tap.

create extension if not exists "pgcrypto";

create type capsule_access_mode as enum ('open', 'private');
create type memory_kind         as enum ('photo', 'video', 'voice', 'text');
create type collaborator_role   as enum ('owner', 'editor');

create table public.capsules (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid references auth.users(id) on delete set null,
  access_mode   capsule_access_mode not null default 'open',
  title         text,
  claimed_at    timestamptz,
  created_at    timestamptz not null default now()
);

create table public.memories (
  id            uuid primary key default gen_random_uuid(),
  capsule_id    uuid not null references public.capsules(id) on delete cascade,
  kind          memory_kind not null,
  storage_path  text,
  text_content  text,
  duration_ms   integer,
  pos_x         real not null default 0,
  pos_y         real not null default 0,
  pos_z         real not null default 0.5,
  created_at    timestamptz not null default now(),
  created_by    uuid references auth.users(id) on delete set null,
  check (
    (kind = 'text'  and text_content is not null) or
    (kind <> 'text' and storage_path is not null)
  ),
  check (pos_x between -1 and 1),
  check (pos_y between -1 and 1),
  check (pos_z between 0 and 1)
);
create index memories_capsule_idx on public.memories (capsule_id, created_at);

create table public.capsule_collaborators (
  capsule_id    uuid not null references public.capsules(id) on delete cascade,
  user_id       uuid not null references auth.users(id) on delete cascade,
  role          collaborator_role not null default 'editor',
  created_at    timestamptz not null default now(),
  primary key (capsule_id, user_id)
);

create table public.capsule_invites (
  token         text primary key,
  capsule_id    uuid not null references public.capsules(id) on delete cascade,
  created_by    uuid not null references auth.users(id) on delete cascade,
  role          collaborator_role not null default 'editor',
  expires_at    timestamptz not null,
  redeemed_at   timestamptz,
  redeemed_by   uuid references auth.users(id) on delete set null,
  created_at    timestamptz not null default now()
);

create table public.access_requests (
  id            uuid primary key default gen_random_uuid(),
  capsule_id    uuid not null references public.capsules(id) on delete cascade,
  requester_id  uuid not null references auth.users(id) on delete cascade,
  message       text,
  status        text not null default 'pending' check (status in ('pending','accepted','declined')),
  created_at    timestamptz not null default now(),
  unique (capsule_id, requester_id)
);

-- ─── helper: is caller a writer (owner or editor) on this capsule? ─────────
create or replace function public.is_capsule_writer(p_capsule uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.capsules c
      where c.id = p_capsule and c.owner_id = auth.uid()
  ) or exists (
    select 1 from public.capsule_collaborators cc
      where cc.capsule_id = p_capsule and cc.user_id = auth.uid()
  );
$$;
revoke all on function public.is_capsule_writer(uuid) from public;
grant execute on function public.is_capsule_writer(uuid) to authenticated, anon;

-- ─── helper: can caller read this capsule? ─────────────────────────────────
create or replace function public.can_read_capsule(p_capsule uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.capsules c
      where c.id = p_capsule
        and (
          c.access_mode = 'open'
          or c.owner_id = auth.uid()
          or exists (
            select 1 from public.capsule_collaborators cc
              where cc.capsule_id = c.id and cc.user_id = auth.uid()
          )
        )
  );
$$;
revoke all on function public.can_read_capsule(uuid) from public;
grant execute on function public.can_read_capsule(uuid) to authenticated, anon;

-- ─── RLS ───────────────────────────────────────────────────────────────────
alter table public.capsules              enable row level security;
alter table public.memories              enable row level security;
alter table public.capsule_collaborators enable row level security;
alter table public.capsule_invites       enable row level security;
alter table public.access_requests       enable row level security;

-- capsules
create policy capsules_select on public.capsules
  for select using (
    access_mode = 'open'
    or owner_id = auth.uid()
    or exists (
      select 1 from public.capsule_collaborators cc
        where cc.capsule_id = capsules.id and cc.user_id = auth.uid()
    )
  );

create policy capsules_update_owner on public.capsules
  for update using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

-- INSERT/DELETE on capsules is handled exclusively by the seeding pipeline
-- (service role). No policy => denied for authenticated/anon.

-- memories
create policy memories_select on public.memories
  for select using (public.can_read_capsule(capsule_id));

create policy memories_insert on public.memories
  for insert with check (
    public.is_capsule_writer(capsule_id) and created_by = auth.uid()
  );

create policy memories_update on public.memories
  for update using (public.is_capsule_writer(capsule_id))
  with check (public.is_capsule_writer(capsule_id));

create policy memories_delete on public.memories
  for delete using (public.is_capsule_writer(capsule_id));

-- collaborators (owner-only writes; reads visible to participants)
create policy collaborators_select on public.capsule_collaborators
  for select using (
    user_id = auth.uid()
    or exists (
      select 1 from public.capsules c
        where c.id = capsule_id and c.owner_id = auth.uid()
    )
  );

create policy collaborators_write on public.capsule_collaborators
  for all using (
    exists (
      select 1 from public.capsules c
        where c.id = capsule_id and c.owner_id = auth.uid()
    )
  ) with check (
    exists (
      select 1 from public.capsules c
        where c.id = capsule_id and c.owner_id = auth.uid()
    )
  );

-- invites: only owner reads/writes; redemption goes through edge fn (service role)
create policy invites_owner on public.capsule_invites
  for all using (
    exists (
      select 1 from public.capsules c
        where c.id = capsule_id and c.owner_id = auth.uid()
    )
  ) with check (
    exists (
      select 1 from public.capsules c
        where c.id = capsule_id and c.owner_id = auth.uid()
    )
  );

-- access requests: requester sees their own; owner sees all on their capsules
create policy access_requests_select on public.access_requests
  for select using (
    requester_id = auth.uid()
    or exists (
      select 1 from public.capsules c
        where c.id = capsule_id and c.owner_id = auth.uid()
    )
  );

create policy access_requests_insert on public.access_requests
  for insert with check (requester_id = auth.uid());

create policy access_requests_update_owner on public.access_requests
  for update using (
    exists (
      select 1 from public.capsules c
        where c.id = capsule_id and c.owner_id = auth.uid()
    )
  );

-- ─── claim RPC: atomic, returns the claimed row or raises 23505 on race ────
create or replace function public.claim_capsule(p_capsule uuid)
returns public.capsules
language plpgsql
security definer
set search_path = public
as $$
declare
  result public.capsules;
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;

  update public.capsules
     set owner_id   = auth.uid(),
         claimed_at = now()
   where id = p_capsule
     and owner_id is null
  returning * into result;

  if not found then
    raise exception 'capsule already claimed or missing' using errcode = '23505';
  end if;

  return result;
end;
$$;
revoke all on function public.claim_capsule(uuid) from public;
grant execute on function public.claim_capsule(uuid) to authenticated;

-- ─── realtime: publish memory changes for live co-editing ──────────────────
alter publication supabase_realtime add table public.memories;
