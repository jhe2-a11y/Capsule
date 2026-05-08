-- Capsule media bucket: private; reads gated by signed URLs from
-- `get-memory-url` Edge Function which re-checks RLS via auth-context client.
-- Direct SELECT/INSERT also enforced here as defense in depth.

insert into storage.buckets (id, name, public, file_size_limit)
values ('capsule-media', 'capsule-media', false, 524288000)
on conflict (id) do nothing;

-- object naming convention: <capsule_id>/<memory_id>.<ext>
-- the first path segment is always the capsule_id.

create or replace function storage.capsule_id_from_path(p_name text)
returns uuid
language sql
immutable
as $$
  select case
    when p_name ~* '^[0-9a-f-]{36}/' then split_part(p_name, '/', 1)::uuid
    else null
  end;
$$;

create policy "capsule-media read"
  on storage.objects for select
  using (
    bucket_id = 'capsule-media'
    and public.can_read_capsule(storage.capsule_id_from_path(name))
  );

create policy "capsule-media insert"
  on storage.objects for insert
  with check (
    bucket_id = 'capsule-media'
    and public.is_capsule_writer(storage.capsule_id_from_path(name))
    and owner = auth.uid()
  );

create policy "capsule-media update"
  on storage.objects for update
  using (
    bucket_id = 'capsule-media'
    and public.is_capsule_writer(storage.capsule_id_from_path(name))
  );

create policy "capsule-media delete"
  on storage.objects for delete
  using (
    bucket_id = 'capsule-media'
    and public.is_capsule_writer(storage.capsule_id_from_path(name))
  );
