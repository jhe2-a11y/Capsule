-- Revoke an outstanding invite by setting its expires_at to the past.
-- Owner-only. Idempotent: revoking an already-redeemed or already-expired
-- invite is a no-op so callers don't have to special-case race conditions.

create or replace function public.revoke_invite(p_token text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  inv public.capsule_invites;
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;

  select * into inv from public.capsule_invites where token = p_token;
  if not found then
    raise exception 'invite not found' using errcode = '02000';
  end if;

  -- Owner check: only the capsule's owner may revoke an invite.
  if not exists (
    select 1 from public.capsules
      where id = inv.capsule_id and owner_id = auth.uid()
  ) then
    raise exception 'not authorized' using errcode = '42501';
  end if;

  -- Idempotent: redeemed or expired invites stay as they are.
  if inv.redeemed_at is null and inv.expires_at > now() then
    update public.capsule_invites
       set expires_at = now()
     where token = p_token;
  end if;
end;
$$;

revoke all on function public.revoke_invite(text) from public;
grant execute on function public.revoke_invite(text) to authenticated;
