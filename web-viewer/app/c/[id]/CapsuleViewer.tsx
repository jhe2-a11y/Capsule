"use client";

import dynamic from "next/dynamic";
import { useCallback, useState } from "react";
import type { CapsuleRow, MemoryRow } from "@/lib/depthField/types";

const DepthFieldScene = dynamic(
  () => import("@/lib/depthField/Scene").then((m) => m.DepthFieldScene),
  { ssr: false, loading: () => <Materializing /> },
);

interface Props {
  capsule: CapsuleRow;
  memories: MemoryRow[];
}

export function CapsuleViewer({ capsule, memories }: Props) {
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

  const [appPrompt, setAppPrompt] = useState<boolean>(true);

  return (
    <main style={{ height: "100vh", position: "relative" }}>
      <DepthFieldScene memories={memories} resolveURL={resolveURL} />

      {appPrompt && (
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
