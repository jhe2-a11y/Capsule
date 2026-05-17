#!/usr/bin/env node
// capsule-storage-smoke — end-to-end test of the storage layer.
//
//   1. Mint an unclaimed `open` capsule via service-role.
//   2. Upload a 1×1 JPEG to capsule-media/<capsule_id>/<memory_id>.jpg
//      (the path scheme the iOS app uses).
//   3. Insert a `memories` row pointing at that path.
//   4. Call the `get-memory-url` edge function with the *anon* key
//      (no Authorization header) — capsule is open, so RLS should
//      permit the read.
//   5. HEAD the signed URL and assert 200 + JPEG content-type.
//   6. Clean up: delete memory, object, capsule.
//
// Run:
//   SUPABASE_URL=https://<ref>.supabase.co \
//   SUPABASE_SERVICE_ROLE_KEY=...           \
//   SUPABASE_ANON_KEY=...                   \
//     node tools/storage-smoke/index.mjs

import { randomUUID } from "node:crypto";

const url     = process.env.SUPABASE_URL;
const service = process.env.SUPABASE_SERVICE_ROLE_KEY;
const anon    = process.env.SUPABASE_ANON_KEY;
if (!url || !service || !anon) {
  console.error("SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, and " +
                "SUPABASE_ANON_KEY are required.");
  process.exit(2);
}

const { createClient } = await import("@supabase/supabase-js");
const admin = createClient(url, service, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const capsuleId = randomUUID();
const memoryId  = randomUUID();
const objectPath = `${capsuleId}/${memoryId}.jpg`;

// Smallest valid JPEG: 1×1 white pixel. Embedded as a base64 literal.
const jpegBytes = Buffer.from(
  "/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////" +
  "////////////////////////////////////////////////////2wBDAf//////////" +
  "////////////////////////////////////////////////////////////////////" +
  "////////////////////wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAA" +
  "AAAAAAr/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFAEBAAAAAAAAAAAAAAAAAAAAAP/E" +
  "ABQRAQAAAAAAAAAAAAAAAAAAAAD/2gAMAwEAAhEDEQA/AL+AB//Z",
  "base64",
);

let ok = false;
try {
  // 1. mint capsule
  const { error: cErr } = await admin.from("capsules")
    .insert({ id: capsuleId, access_mode: "open" });
  if (cErr) throw new Error(`mint capsule: ${cErr.message}`);
  log("minted capsule", capsuleId);

  // 2. upload object
  const { error: uErr } = await admin.storage
    .from("capsule-media")
    .upload(objectPath, jpegBytes, {
      contentType: "image/jpeg",
      upsert: false,
    });
  if (uErr) throw new Error(`upload: ${uErr.message}`);
  log("uploaded", objectPath);

  // 3. insert memory
  const { error: mErr } = await admin.from("memories").insert({
    id: memoryId,
    capsule_id: capsuleId,
    kind: "photo",
    storage_path: objectPath,
    pos_x: 0, pos_y: 0, pos_z: 0.5,
  });
  if (mErr) throw new Error(`insert memory: ${mErr.message}`);
  log("inserted memory row");

  // 4. call get-memory-url with anon (no auth header)
  const fnUrl = `${url.replace(/\/$/, "")}/functions/v1/get-memory-url`;
  const fnRes = await fetch(fnUrl, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "apikey": anon,
      "Authorization": `Bearer ${anon}`,
    },
    body: JSON.stringify({ memory_id: memoryId }),
  });
  if (!fnRes.ok) {
    const t = await fnRes.text().catch(() => "");
    throw new Error(`get-memory-url ${fnRes.status}: ${t}`);
  }
  const fnBody = await fnRes.json();
  if (!fnBody?.url) throw new Error(`get-memory-url body missing url`);
  log("signed url issued");

  // 5. HEAD the signed URL
  const headRes = await fetch(fnBody.url, { method: "HEAD" });
  if (headRes.status !== 200) {
    throw new Error(`signed url HEAD ${headRes.status}`);
  }
  const ct = headRes.headers.get("content-type") ?? "";
  if (!ct.startsWith("image/jpeg")) {
    throw new Error(`unexpected content-type: ${ct}`);
  }
  log("signed url HEAD 200", ct);

  ok = true;
} catch (err) {
  console.error(`FAIL: ${err.message}`);
} finally {
  // 6. cleanup — best-effort, doesn't change exit code
  await admin.from("memories").delete().eq("id", memoryId);
  await admin.storage.from("capsule-media").remove([objectPath]);
  await admin.from("capsules").delete().eq("id", capsuleId);
  log("cleaned up");
}

if (ok) {
  console.log("ok: upload → memory → signed URL → 200");
  process.exit(0);
} else {
  process.exit(1);
}

function log(...parts) { console.error("·", ...parts); }
