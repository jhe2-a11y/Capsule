-- Mirror of accept_access_request: flips a pending request to 'declined'
-- without granting collaborator access. SECURITY DEFINER so the call
-- doesn't depend on the client's RLS write paths; we re-check ownership
-- explicitly inside.

create or replace function public.decline_access_request(p_request uuid)
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

  -- Owner check: only the capsule's owner may decline.
  if not exists (
    select 1 from public.capsules
      where id = req.capsule_id and owner_id = auth.uid()
  ) then
    raise exception 'not authorized' using errcode = '42501';
  end if;

  update public.access_requests
     set status = 'declined'
   where id = p_request;
end;
$$;

revoke all on function public.decline_access_request(uuid) from public;
grant execute on function public.decline_access_request(uuid) to authenticated;
