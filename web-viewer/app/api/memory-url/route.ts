import { NextResponse } from "next/server";
import { serverClient } from "@/lib/supabase/server";

export async function POST(req: Request) {
  const body = await req.json().catch(() => ({}));
  const memoryID = body?.memory_id as string | undefined;
  if (!memoryID) return NextResponse.json({ error: "memory_id required" }, { status: 400 });

  const supabase = serverClient();

  // RLS-aware read: if the caller can SELECT the memory row, they may view
  // its media. We then issue a short-lived signed URL.
  const { data: memory, error } = await supabase
    .from("memories")
    .select("id, capsule_id, storage_path, kind")
    .eq("id", memoryID)
    .maybeSingle();

  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  if (!memory) return NextResponse.json({ error: "not_found" }, { status: 404 });
  if (!memory.storage_path) return NextResponse.json({ error: "no_media" }, { status: 400 });

  const { data: signed, error: sErr } = await supabase.storage
    .from("capsule-media")
    .createSignedUrl(memory.storage_path, 60 * 30);

  if (sErr) return NextResponse.json({ error: sErr.message }, { status: 500 });
  return NextResponse.json({ url: signed.signedUrl, kind: memory.kind });
}
