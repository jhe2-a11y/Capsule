import { preflight, jsonResponse } from "../_shared/cors.ts";
import { userClient, serviceClient } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  const pf = preflight(req);
  if (pf) return pf;
  if (req.method !== "POST") return jsonResponse({ error: "method" }, 405);

  const { memory_id } = await req.json().catch(() => ({}));
  if (!memory_id) return jsonResponse({ error: "memory_id required" }, 400);

  // RLS-aware read first; if user can SELECT the memory row, they can view it.
  const u = userClient(req);
  const { data: memory, error: mErr } = await u
    .from("memories")
    .select("id, capsule_id, storage_path, kind")
    .eq("id", memory_id)
    .maybeSingle();

  if (mErr) return jsonResponse({ error: mErr.message }, 400);
  if (!memory) return jsonResponse({ error: "not_found" }, 404);
  if (!memory.storage_path) return jsonResponse({ error: "no_media" }, 400);

  const svc = serviceClient();
  const { data: signed, error: sErr } = await svc.storage
    .from("capsule-media")
    .createSignedUrl(memory.storage_path, 60 * 30);

  if (sErr) return jsonResponse({ error: sErr.message }, 500);
  return jsonResponse({ url: signed.signedUrl, kind: memory.kind });
});
