-- When a memory row is deleted, also delete its companion object in the
-- capsule-media bucket. Without this trigger, deleting a memory leaves an
-- orphaned file in storage that is no longer reachable via signed URLs
-- (the memory_id is gone) but still consumes disk + costs.
--
-- The trigger runs SECURITY DEFINER so it works regardless of whether the
-- deleter is the capsule owner, an editor, or a service-role process —
-- the upstream RLS DELETE policy on public.memories has already verified
-- the caller is authorized to remove this row, so this trigger inherits
-- that authorization.

create or replace function public.cascade_delete_memory_object()
returns trigger
language plpgsql
security definer
set search_path = public, storage
as $$
begin
  if old.storage_path is not null then
    delete from storage.objects
     where bucket_id = 'capsule-media'
       and name = old.storage_path;
  end if;
  return old;
end;
$$;

drop trigger if exists cascade_delete_memory_object on public.memories;

create trigger cascade_delete_memory_object
after delete on public.memories
for each row
execute function public.cascade_delete_memory_object();
