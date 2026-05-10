-- Atomic accept_access_request: flips the request to 'accepted' and
-- inserts the requester into capsule_collaborators in a single
-- transaction. SECURITY DEFINER so the call doesn't have to navigate
-- two RLS-permitted writes from the client; we re-check ownership
-- explicitly inside.
create or replace function public.accept_access_request(p_request uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  req public.access_requests;
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;

  select * into req from public.access_requests where id = p_request;
  if not found then
    raise exception 'access request not found' using errcode = '02000';
  end if;
  if req.status <> 'pending' then
    raise exception 'access request already resolved' using errcode = '23514';
  end if;

  -- Owner check: only the capsule's owner may accept.
  if not exists (
    select 1 from public.capsules
      where id = req.capsule_id and owner_id = auth.uid()
  ) then
    raise exception 'not authorized' using errcode = '42501';
  end if;

  update public.access_requests
     set status = 'accepted'
   where id = p_request;

  insert into public.capsule_collaborators (capsule_id, user_id, role)
       values (req.capsule_id, req.requester_id, 'editor')
  on conflict (capsule_id, user_id) do nothing;
end;
$$;

revoke all on function public.accept_access_request(uuid) from public;
grant execute on function public.accept_access_request(uuid) to authenticated;

-- Add `capsules` to the realtime publication so the iOS app and the web
-- viewer can react to title / access_mode changes the moment the owner
-- toggles them. (memories was added in 0001_init.sql.)
alter publication supabase_realtime add table public.capsules;
