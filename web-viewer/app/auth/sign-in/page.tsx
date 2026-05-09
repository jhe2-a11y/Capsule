"use client";

import { useState } from "react";
import { browserClient } from "@/lib/supabase/client";

export default function SignIn({
  searchParams,
}: { searchParams?: { next?: string } }) {
  const [email, setEmail] = useState("");
  const [sent, setSent] = useState(false);
  const [working, setWorking] = useState(false);
  const next = searchParams?.next ?? "/";

  async function send() {
    if (!email || working) return;
    setWorking(true);
    const supabase = browserClient();
    const redirect = typeof window !== "undefined"
      ? `${window.location.origin}/auth/callback?next=${encodeURIComponent(next)}`
      : undefined;
    const { error } = await supabase.auth.signInWithOtp({
      email,
      options: { emailRedirectTo: redirect },
    });
    setWorking(false);
    if (!error) setSent(true);
  }

  return (
    <main style={{
      height: "100vh", display: "flex", alignItems: "center",
      justifyContent: "center", flexDirection: "column", gap: 18,
      padding: 32,
    }}>
      <div style={{ fontSize: 22, letterSpacing: 1 }}>Sign in</div>
      {sent ? (
        <div style={{ opacity: 0.65, fontStyle: "italic", textAlign: "center", maxWidth: 380 }}>
          A link is on its way. Open it on this device to continue.
        </div>
      ) : (
        <>
          <input
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            placeholder="you@example.com"
            type="email"
            style={{
              padding: "12px 16px", borderRadius: 999,
              background: "rgba(255,255,255,0.06)",
              border: "0.5px solid rgba(255,255,255,0.12)",
              color: "#fff", width: 320, textAlign: "center",
            }}
          />
          <button
            onClick={send}
            disabled={working}
            style={{
              padding: "12px 24px", borderRadius: 999,
              background: "rgba(255,255,255,0.92)", color: "#000",
              opacity: working ? 0.5 : 1, border: 0,
            }}
          >
            {working ? "…" : "Send link"}
          </button>
        </>
      )}
    </main>
  );
}
