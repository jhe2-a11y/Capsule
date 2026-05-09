"use client";

import dynamic from "next/dynamic";
import { useCallback, useEffect, useMemo, useState } from "react";
import type { CapsuleRow, MemoryRow } from "@/lib/depthField/types";
import { Foreground } from "@/lib/depthField/Foreground";
import { browserClient } from "@/lib/supabase/client";

const DepthFieldScene = dynamic(
  () => import("@/lib/depthField/Scene").then((m) => m.DepthFieldScene),
  { ssr: false, loading: () => <Materializing /> },
);

interface Props {
  capsule: CapsuleRow;
  memories: MemoryRow[];
}

export function CapsuleViewer({ capsule, memories: initial }: Props) {
  const [memories, setMemories] = useState<MemoryRow[]>(initial);
  const [focused, setFocused] = useState<string | null>(null);
  const [appPrompt, setAppPrompt] = useState<boolean>(true);

  const focusedMemory = useMemo(
    () => memories.find((m) => m.id === focused) ?? null,
    [memories, focused],
  );

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
          setMemories((prev) =>
            prev.some((m) => m.id === row.id) ? prev : [...prev, row]);
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
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [capsule.id]);

  // Esc closes the foreground overlay (parity with the iOS swipe-down).
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") setFocused(null);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  return (
    <main style={{ height: "100vh", position: "relative" }}>
      <DepthFieldScene
        memories={memories}
        resolveURL={resolveURL}
        focused={focused}
        onFocusChange={setFocused}
      />

      {focusedMemory && (
        <Foreground
          memory={focusedMemory}
          resolveURL={resolveURL}
          onDismiss={() => setFocused(null)}
        />
      )}

      {appPrompt && !focusedMemory && (
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

function Materializing() {
  return (
    <div style={{
      height: "100vh", display: "flex",
      alignItems: "center", justifyContent: "center",
    }}>
      <div style={{
        width: 220, height: 220, borderRadius: "50%",
        background: "radial-gradient(circle, rgba(255,255,255,0.08), transparent 60%)",
        filter: "blur(28px)",
      }} />
    </div>
  );
}
