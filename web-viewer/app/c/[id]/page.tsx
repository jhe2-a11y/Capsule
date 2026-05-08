import { notFound } from "next/navigation";
import { serverClient } from "@/lib/supabase/client";
import type { CapsuleRow, MemoryRow } from "@/lib/depthField/types";
import { CapsuleViewer } from "./CapsuleViewer";

export const dynamic = "force-dynamic";

interface Props { params: { id: string } }

export default async function Page({ params }: Props) {
  const supabase = serverClient();

  const { data: capsule, error: cErr } = await supabase
    .from("capsules")
    .select("*")
    .eq("id", params.id)
    .maybeSingle<CapsuleRow>();

  if (cErr) {
    return <FailureScreen kind="error" />;
  }

  // RLS will return null both for "not found" and "private + not allowed".
  // From the consumer's perspective both should surface the private state.
  if (!capsule) {
    return <PrivateOrMissing capsuleID={params.id} />;
  }

  const { data: memories } = await supabase
    .from("memories")
    .select("*")
    .eq("capsule_id", capsule.id)
    .order("created_at", { ascending: true })
    .returns<MemoryRow[]>();

  return <CapsuleViewer capsule={capsule} memories={memories ?? []} />;
}

function PrivateOrMissing({ capsuleID }: { capsuleID: string }) {
  return (
    <main style={{
      height: "100vh", display: "flex",
      alignItems: "center", justifyContent: "center",
      flexDirection: "column", gap: 12, textAlign: "center", padding: 32,
    }}>
      <div style={{
        width: 92, height: 92, borderRadius: "50%",
        border: "0.5px solid rgba(255,255,255,0.18)",
      }} />
      <div style={{ fontSize: 20 }}>This Capsule is private.</div>
      <div style={{ opacity: 0.55, fontStyle: "italic" }}>
        Sign in to see if you can open it.
      </div>
      <a
        href={`/auth/sign-in?next=/c/${capsuleID}`}
        style={{
          marginTop: 16, padding: "12px 24px",
          borderRadius: 999, background: "rgba(255,255,255,0.92)",
          color: "#000",
        }}
      >
        Sign in
      </a>
    </main>
  );
}

function FailureScreen({ kind }: { kind: "error" }) {
  return (
    <main style={{
      height: "100vh", display: "flex", alignItems: "center",
      justifyContent: "center",
    }}>
      <div style={{ opacity: 0.55, fontStyle: "italic" }}>Something stirred.</div>
    </main>
  );
}
