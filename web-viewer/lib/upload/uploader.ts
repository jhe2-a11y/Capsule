import type { MemoryKind, MemoryRow } from "@/lib/depthField/types";
import { browserClient } from "@/lib/supabase/client";

export interface UploadArgs {
  capsuleId: string;
  // Caller-provided UUID. The viewer pre-generates this so the optimistic
  // local row and the server row share an id — realtime INSERT then becomes
  // a no-op for our own uploads instead of a duplicate.
  memoryId: string;
  position: { x: number; y: number; z: number };
  userId: string;
  // Either `file` (for photo/video/voice) or `text` (for text memories).
  file?: File;
  text?: string;
  kind: MemoryKind;
}

// Mirrors the iOS contract in CapsuleAPI.swift uploadMedia(): same storage
// path scheme (<capsule_id>/<memory_id>.<ext>) and same insertion order
// (storage first, then memories row). Bypasses any new edge function — RLS
// + storage policies are the gate.
export async function uploadMemory(args: UploadArgs): Promise<MemoryRow> {
  const supabase = browserClient();
  const memoryId = args.memoryId;
  let storagePath: string | null = null;

  if (args.kind === "text") {
    if (!args.text || !args.text.trim()) {
      throw new Error("Text memory is empty.");
    }
  } else {
    if (!args.file) throw new Error("No file provided for media memory.");
    const ext = extFor(args.kind, args.file.type, args.file.name);
    storagePath = `${args.capsuleId}/${memoryId}${ext}`;

    const { error: uploadErr } = await supabase
      .storage
      .from("capsule-media")
      .upload(storagePath, args.file, {
        contentType: args.file.type || undefined,
        upsert: false,
      });
    if (uploadErr) throw uploadErr;
  }

  const duration = args.kind === "voice" && args.file
    ? await probeAudioDurationMs(args.file)
    : null;

  const insertPayload = {
    id: memoryId,
    capsule_id: args.capsuleId,
    kind: args.kind,
    storage_path: storagePath,
    text_content: args.kind === "text" ? (args.text ?? "").trim() : null,
    duration_ms: duration,
    pos_x: args.position.x,
    pos_y: args.position.y,
    pos_z: args.position.z,
    created_by: args.userId,
  };

  const { data, error } = await supabase
    .from("memories")
    .insert(insertPayload)
    .select()
    .single();

  if (error) {
    // Best-effort cleanup of the orphaned storage object. We don't await
    // hard — if cleanup fails the eventual cascade-delete trigger (Phase 3)
    // will sweep it. We still throw the original error.
    if (storagePath) {
      void supabase.storage.from("capsule-media").remove([storagePath]);
    }
    throw error;
  }

  return data as MemoryRow;
}

export function inferKindFromMime(mime: string): MemoryKind | null {
  if (!mime) return null;
  if (mime.startsWith("image/")) return "photo";
  if (mime.startsWith("video/")) return "video";
  if (mime.startsWith("audio/")) return "voice";
  return null;
}

function extFor(kind: MemoryKind, mime: string, name: string): string {
  // Prefer the filename extension when sensible so MOV stays MOV, PNG stays
  // PNG, etc. Fall back to MIME-derived defaults matching the iOS contract.
  const fromName = name.includes(".") ? name.slice(name.lastIndexOf(".")).toLowerCase() : "";
  if (fromName && /^\.[a-z0-9]{2,5}$/.test(fromName)) return fromName;

  if (kind === "photo") {
    if (mime === "image/png") return ".png";
    if (mime === "image/webp") return ".webp";
    if (mime === "image/heic") return ".heic";
    return ".jpg";
  }
  if (kind === "video") {
    if (mime === "video/quicktime") return ".mov";
    if (mime === "video/webm") return ".webm";
    return ".mp4";
  }
  if (kind === "voice") {
    if (mime === "audio/mpeg") return ".mp3";
    if (mime === "audio/wav") return ".wav";
    return ".m4a";
  }
  return "";
}

function probeAudioDurationMs(file: File): Promise<number | null> {
  return new Promise((resolve) => {
    try {
      const url = URL.createObjectURL(file);
      const a = new Audio();
      a.preload = "metadata";
      a.onloadedmetadata = () => {
        const ms = Math.round((a.duration || 0) * 1000);
        URL.revokeObjectURL(url);
        resolve(Number.isFinite(ms) && ms > 0 ? ms : null);
      };
      a.onerror = () => { URL.revokeObjectURL(url); resolve(null); };
      a.src = url;
    } catch {
      resolve(null);
    }
  });
}
