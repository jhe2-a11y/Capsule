import { serverClient } from "@/lib/supabase/server";
import type { CapsuleRow, MemoryRow } from "@/lib/depthField/types";
import { CapsuleViewer } from "./CapsuleViewer";

export const dynamic = "force-dynamic";

interface Props { params: { id: string } }

export default async function Page({ params }: Props) {
  const supabase = serverClient();

  const cRes = await supabase
    .from("capsules")
    .select("*")
    .eq("id", params.id)
    .maybeSingle();

  if (cRes.error) {
    return <FailureScreen capsuleID={params.id} />;
  }

  const capsule = cRes.data as CapsuleRow | null;

  // RLS returns null both for "not found" and "private + not allowed". From
  // the consumer's perspective both surface the private state.
  if (!capsule) {
    return <PrivateOrMissing capsuleID={params.id} />;
  }

  const mRes = await supabase
    .from("memories")
    .select("*")
    .eq("capsule_id", capsule.id)
    .order("created_at", { ascending: true });

  if (mRes.error) {
    return <FailureScreen capsuleID={params.id} />;
  }

  const memories = (mRes.data ?? []) as MemoryRow[];

  return <CapsuleViewer capsule={capsule} memories={memories} />;
}

function PrivateOrMissing({ capsuleID }: { capsuleID: string }) {
  return (
    <main role="main" style={screenStyle}>
      <div aria-hidden style={{
        width: 92, height: 92, borderRadius: "50%",
        border: "0.5px solid rgba(255,255,255,0.18)",
      }} />
      <div style={{ fontSize: 20 }}>This Capsule is private.</div>
      <div style={{ opacity: 0.55, fontStyle: "italic", maxWidth: 320 }}>
        Sign in with the email the owner shared with you, or ask them for an invite.
      </div>
      <a
        href={`/auth/sign-in?next=/c/${capsuleID}`}
        style={primaryButton}
      >
        Sign in
      </a>
    </main>
  );
}

function FailureScreen({ capsuleID }: { capsuleID: string }) {
  return (
    <main role="main" style={screenStyle}>
      <div aria-hidden style={{
        width: 92, height: 92, borderRadius: "50%",
        border: "0.5px solid rgba(255,255,255,0.18)",
      }} />
      <div style={{ fontSize: 20 }}>Couldn’t open this Capsule.</div>
      <div style={{ opacity: 0.55, fontStyle: "italic", maxWidth: 320 }}>
        Something stirred on the way back. Try again in a moment.
      </div>
      <a href={`/c/${capsuleID}`} style={primaryButton}>
        Try again
      </a>
    </main>
  );
}

const screenStyle: React.CSSProperties = {
  height: "100vh", display: "flex",
  alignItems: "center", justifyContent: "center",
  flexDirection: "column", gap: 14, textAlign: "center", padding: 32,
};

const primaryButton: React.CSSProperties = {
  marginTop: 16, padding: "12px 24px",
  borderRadius: 999, background: "rgba(255,255,255,0.92)",
  color: "#000", fontSize: 15,
};
