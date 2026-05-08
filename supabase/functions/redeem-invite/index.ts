import { preflight, jsonResponse } from "../_shared/cors.ts";
import { requireUser, serviceClient } from "../_shared/supabase.ts";


Deno.serve(async (req) => {
  const pf = preflight(req);
  if (pf) return pf;
  if (req.method !== "POST") return jsonResponse({ error: "method" }, 405);

  let user;
  try { ({ user } = await requireUser(req)); }
  catch (r) { return r as Response; }

  const { token } = await req.json().catch(() => ({}));
  if (!token) return jsonResponse({ error: "token required" }, 400);

  const svc = serviceClient();
  const { data: invite, error: iErr } = await svc
    .from("capsule_invites")
    .select("*")
    .eq("token", token)
    .maybeSingle();

  if (iErr) return jsonResponse({ error: iErr.message }, 500);
  if (!invite) return jsonResponse({ error: "invalid_token" }, 404);
  if (invite.redeemed_at) return jsonResponse({ error: "already_redeemed" }, 410);
  if (new Date(invite.expires_at) < new Date()) {
    return jsonResponse({ error: "expired" }, 410);
  }

  const { error: cErr } = await svc.from("capsule_collaborators").upsert({
    capsule_id: invite.capsule_id,
    user_id:    user.id,
    role:       invite.role,
  });
  if (cErr) return jsonResponse({ error: cErr.message }, 500);

  await svc.from("capsule_invites")
    .update({ redeemed_at: new Date().toISOString(), redeemed_by: user.id })
    .eq("token", token);

  return jsonResponse({ capsule_id: invite.capsule_id, role: invite.role });
});
