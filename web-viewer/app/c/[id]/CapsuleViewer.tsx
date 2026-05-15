"use client";

import dynamic from "next/dynamic";
import { useCallback, useEffect, useMemo, useState } from "react";
import type { CapsuleRow, LocalMemory, MemoryKind, MemoryRow } from "@/lib/depthField/types";
import { Foreground } from "@/lib/depthField/Foreground";
import { browserClient } from "@/lib/supabase/client";
import { relativeTime } from "@/lib/format/relativeTime";
import { useCapsuleRole, canWrite as roleCanWrite } from "@/lib/upload/useCapsuleRole";
import { useDropzone, type DropPayload } from "@/lib/upload/useDropzone";
import { pickFreeSpot } from "@/lib/upload/freeSpot";
import { inferKindFromMime, uploadMemory } from "@/lib/upload/uploader";
import { DropPill } from "@/components/DropPill";
import { DropOverlay } from "@/components/DropOverlay";

const DepthFieldScene = dynamic(
  () => import("@/lib/depthField/Scene").then((m) => m.DepthFieldScene),
  { ssr: false, loading: () => <Materializing /> },
);

interface Props {
  capsule: CapsuleRow;
  memories: MemoryRow[];
}

export function CapsuleViewer({ capsule: initialCapsule, memories: initial }: Props) {
  const [capsule, setCapsule] = useState<CapsuleRow>(initialCapsule);
  const [memories, setMemories] = useState<LocalMemory[]>(initial);
  const [focused, setFocused] = useState<string | null>(null);
  const [appPrompt, setAppPrompt] = useState<boolean>(true);

  const roleState = useCapsuleRole(capsule.id, capsule.owner_id);
  const canWrite = roleCanWrite(roleState.role);

  const focusedMemory = useMemo(
    () => memories.find((m) => m.id === focused) ?? null,
    [memories, focused],
  );

  // Tiles in-flight or in an error state aren't openable. Clicking an errored
  // tile dismisses it from local state (the user can re-pick the file).
  const handleFocusChange = useCallback((id: string | null) => {
    if (id === null) { setFocused(null); return; }
    const m = memories.find((x) => x.id === id);
    if (m?.inFlight) return;
    if (m?.uploadError) {
      setMemories((prev) => prev.filter((x) => x.id !== id));
      return;
    }
    setFocused(id);
  }, [memories]);

  const resolveURL = useCallback(async (memoryID: string): Promise<string | null> => {
    try {
      const r = await fetch("/api/memory-url", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ memory_id: memoryID }),
      });
      if (!r.ok) return null;
      const j = await r.json() as { url?: string };
      return j.url ?? null;
    } catch {
      return null;
    }
  }, []);

  // Live updates: another owner / collaborator editing this capsule on iOS or
  // another browser session causes new nodes to materialize here without a
  // refresh. The Realtime channel mirrors the iOS one (capsule:<id>).
  useEffect(() => {
    const supabase = browserClient();
    const channel = supabase.channel(`capsule:${capsule.id}`);

    channel
      .on(
        "postgres_changes",
        { event: "INSERT", schema: "public", table: "memories",
          filter: `capsule_id=eq.${capsule.id}` },
        (payload) => {
          const row = payload.new as MemoryRow;
          // Reconcile-by-id: if we already have a local optimistic row with
          // this id (our own upload), replace it; otherwise append.
          setMemories((prev) => {
            const existing = prev.findIndex((m) => m.id === row.id);
            if (existing >= 0) {
              const next = prev.slice();
              next[existing] = row;
              return next;
            }
            return [...prev, row];
          });
        },
      )
      .on(
        "postgres_changes",
        { event: "UPDATE", schema: "public", table: "memories",
          filter: `capsule_id=eq.${capsule.id}` },
        (payload) => {
          const row = payload.new as MemoryRow;
          setMemories((prev) => prev.map((m) => (m.id === row.id ? row : m)));
        },
      )
      .on(
        "postgres_changes",
        { event: "DELETE", schema: "public", table: "memories",
          filter: `capsule_id=eq.${capsule.id}` },
        (payload) => {
          const oldRow = payload.old as Partial<MemoryRow>;
          if (!oldRow.id) return;
          setMemories((prev) => prev.filter((m) => m.id !== oldRow.id));
          setFocused((cur) => (cur === oldRow.id ? null : cur));
        },
      )
      .on(
        "postgres_changes",
        { event: "UPDATE", schema: "public", table: "capsules",
          filter: `id=eq.${capsule.id}` },
        (payload) => {
          const row = payload.new as CapsuleRow;
          setCapsule(row);
          // If the owner just flipped the capsule to private and the
          // current viewer is anonymous, RLS will start denying memory
          // reads on subsequent fetches. We don't tear down the existing
          // memories — they were already returned to this session — but
          // future deltas will simply stop arriving.
        },
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [capsule.id]);

  // Keyboard navigation: Esc closes; arrows traverse the field; Enter opens
  // the nearest memory when nothing is focused.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        setFocused(null);
        return;
      }
      if (memories.length === 0) return;

      const dir = arrowDirection(e.key);
      if (dir) {
        e.preventDefault();
        setFocused((cur) => {
          if (cur === null) return centermostId(memories);
          const next = neighborInDirection(memories, cur, dir);
          return next ?? cur;
        });
        return;
      }
      if (e.key === "Enter" && focused === null) {
        e.preventDefault();
        setFocused(centermostId(memories));
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [memories, focused]);

  // Optimistic insert + upload + reconcile.
  const startUpload = useCallback((payload: DropPayload) => {
    if (!roleState.userId) return;
    if (!canWrite) return;

    const kind: MemoryKind | null = payload.kind === "text"
      ? "text"
      : inferKindFromMime(payload.file.type);
    if (!kind) return;

    const userId = roleState.userId;
    const spot = pickFreeSpot(memories);
    const memoryId = crypto.randomUUID();
    const optimistic: LocalMemory = {
      id: memoryId,
      capsule_id: capsule.id,
      kind,
      storage_path: null,
      text_content: payload.kind === "text" ? payload.text : null,
      duration_ms: null,
      pos_x: spot.x, pos_y: spot.y, pos_z: spot.z,
      created_at: new Date().toISOString(),
      created_by: userId,
      inFlight: true,
    };
    setMemories((prev) => [...prev, optimistic]);

    void (async () => {
      try {
        const real = await uploadMemory({
          capsuleId: capsule.id,
          memoryId,
          userId,
          position: spot,
          kind,
          file: payload.kind === "file" ? payload.file : undefined,
          text: payload.kind === "text" ? payload.text : undefined,
        });
        setMemories((prev) => prev.map((m) => (m.id === memoryId ? real : m)));
      } catch (err) {
        setMemories((prev) => prev.map((m) =>
          m.id === memoryId
            ? { ...m, inFlight: false, uploadError: errorMessage(err) }
            : m
        ));
      }
    })();
  }, [capsule.id, canWrite, memories, roleState.userId]);

  const { isDraggingOver } = useDropzone({
    enabled: !roleState.loading,
    onAccept: startUpload,
  });

  const handleFilesPicked = useCallback((files: File[]) => {
    if (!canWrite) return;
    for (const file of files) {
      startUpload({ kind: "file", file });
    }
  }, [canWrite, startUpload]);

  const handleRequestAccess = useCallback(async (): Promise<boolean> => {
    if (!roleState.userId) {
      window.location.href = `/auth/sign-in?next=/c/${capsule.id}`;
      return false;
    }
    try {
      const supabase = browserClient();
      const { error } = await supabase.functions.invoke("request-access", {
        body: { capsule_id: capsule.id },
      });
      return !error;
    } catch {
      return false;
    }
  }, [capsule.id, roleState.userId]);

  return (
    <main style={{ height: "100vh", position: "relative" }}>
      <DepthFieldScene
        memories={memories}
        resolveURL={resolveURL}
        focused={focused}
        onFocusChange={handleFocusChange}
      />

      {/* Screen-reader & keyboard-friendly parallel list of memories. Visually
          hidden but reachable via Tab. Each item activates the same focus
          state as a click in the 3D scene. */}
      <ul style={srOnly} aria-label="Capsule memories">
        {memories.map((m) => (
          <li key={m.id}>
            <button
              onClick={() => setFocused(m.id)}
              aria-label={`Open ${labelFor(m.kind)} memory added ${relativeTime(m.created_at)}`}
            >
              {labelFor(m.kind)} — {relativeTime(m.created_at)}
            </button>
          </li>
        ))}
      </ul>

      {focusedMemory && (
        <Foreground
          memory={focusedMemory}
          resolveURL={resolveURL}
          onDismiss={() => setFocused(null)}
        />
      )}

      {!focusedMemory && canWrite && (
        <DropPill onFilesPicked={handleFilesPicked} />
      )}

      <DropOverlay
        visible={isDraggingOver}
        canWrite={canWrite}
        onRequestAccess={canWrite ? undefined : handleRequestAccess}
      />

      {appPrompt && !focusedMemory && !isDraggingOver && (
        <div
          style={{
            position: "absolute", bottom: 28, left: 0, right: 0,
            display: "flex", justifyContent: "center", pointerEvents: "auto",
          }}
        >
          <a
            href={`capsule://c/${capsule.id}`}
            onClick={() => setTimeout(() => setAppPrompt(false), 800)}
            style={{
              padding: "10px 18px", borderRadius: 999,
              background: "rgba(255,255,255,0.06)",
              backdropFilter: "blur(20px)",
              border: "0.5px solid rgba(255,255,255,0.12)",
              fontStyle: "italic", opacity: 0.85,
            }}
          >
            Open in the Capsule app
          </a>
        </div>
      )}
    </main>
  );
}

const srOnly: React.CSSProperties = {
  position: "absolute", width: 1, height: 1,
  padding: 0, margin: -1, overflow: "hidden",
  clip: "rect(0,0,0,0)", whiteSpace: "nowrap", border: 0,
};

function labelFor(kind: MemoryKind): string {
  switch (kind) {
    case "text":  return "Note";
    case "photo": return "Photo";
    case "video": return "Video";
    case "voice": return "Voice";
  }
}

type Dir = "left" | "right" | "up" | "down";

function arrowDirection(key: string): Dir | null {
  switch (key) {
    case "ArrowLeft":  return "left";
    case "ArrowRight": return "right";
    case "ArrowUp":    return "up";
    case "ArrowDown":  return "down";
    default: return null;
  }
}

function centermostId(memories: LocalMemory[]): string | null {
  if (memories.length === 0) return null;
  let bestId = memories[0].id;
  let bestDist = Infinity;
  for (const m of memories) {
    const d = m.pos_x * m.pos_x + m.pos_y * m.pos_y;
    if (d < bestDist) { bestDist = d; bestId = m.id; }
  }
  return bestId;
}

function neighborInDirection(memories: LocalMemory[], fromId: string, dir: Dir): string | null {
  const cur = memories.find((m) => m.id === fromId);
  if (!cur) return null;
  let bestId: string | null = null;
  let bestScore = Infinity;
  for (const m of memories) {
    if (m.id === fromId) continue;
    const dx = m.pos_x - cur.pos_x;
    const dy = m.pos_y - cur.pos_y;
    let along = 0, across = 0;
    switch (dir) {
      case "left":  along = -dx; across = Math.abs(dy); break;
      case "right": along =  dx; across = Math.abs(dy); break;
      case "up":    along =  dy; across = Math.abs(dx); break;
      case "down":  along = -dy; across = Math.abs(dx); break;
    }
    if (along <= 0.001) continue; // candidate is not in the chosen direction
    const score = along + across * 2;
    if (score < bestScore) { bestScore = score; bestId = m.id; }
  }
  return bestId;
}

function errorMessage(e: unknown): string {
  if (e instanceof Error) return e.message;
  if (typeof e === "string") return e;
  return "Upload failed.";
}

function Materializing() {
  return (
    <div
      aria-label="Loading Capsule"
      style={{
        height: "100vh", display: "flex",
        alignItems: "center", justifyContent: "center",
      }}
    >
      <div style={{
        width: 220, height: 220, borderRadius: "50%",
        background: "radial-gradient(circle, rgba(255,255,255,0.08), transparent 60%)",
        filter: "blur(28px)",
        animation: "capsule-pulse 2.4s ease-in-out infinite",
      }} />
      <style>{`
        @keyframes capsule-pulse {
          0%, 100% { opacity: 0.55; transform: scale(1); }
          50%      { opacity: 1;    transform: scale(1.04); }
        }
      `}</style>
    </div>
  );
}
