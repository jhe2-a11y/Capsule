import { preflight, jsonResponse } from "../_shared/cors.ts";
import { userClient } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  const pf = preflight(req);
  if (pf) return pf;
  if (req.method !== "POST") return jsonResponse({ error: "method" }, 405);

  const { memory_id } = await req.json().catch(() => ({}));
  if (!memory_id) return jsonResponse({ error: "memory_id required" }, 400);

  // RLS-aware read: if the caller can SELECT the memory row, they may view
  // its media. Sign with the *same* user-context client so RLS gates the
  // sign step too — service-role would silently bypass it.
  const u = userClient(req);
  const { data: memory, error: mErr } = await u
    .from("memories")
    .select("id, capsule_id, storage_path, kind")
    .eq("id", memory_id)
    .maybeSingle();

  if (mErr) return jsonResponse({ error: mErr.message }, 400);
  if (!memory) return jsonResponse({ error: "not_found" }, 404);
  if (!memory.storage_path) return jsonResponse({ error: "no_media" }, 400);

  const { data: signed, error: sErr } = await u.storage
    .from("capsule-media")
    .createSignedUrl(memory.storage_path, 60 * 30);

  if (sErr || !signed?.signedUrl) {
    return jsonResponse({ error: sErr?.message ?? "sign_failed" }, 500);
  }
  return jsonResponse({ url: signed.signedUrl, kind: memory.kind });
});
