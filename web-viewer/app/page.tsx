import Link from "next/link";
import { redirect } from "next/navigation";

import { serverClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export default async function Home() {
  const supabase = serverClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (user) {
    redirect("/dashboard");
  }

  return (
    <main style={{
      display: "flex", height: "100vh",
      alignItems: "center", justifyContent: "center",
      flexDirection: "column", gap: 16,
    }}>
      <div style={{
        width: 88, height: 88, borderRadius: "50%",
        border: "0.5px solid rgba(255,255,255,0.18)",
        background: "rgba(255,255,255,0.04)",
      }} />
      <div style={{ letterSpacing: 2, opacity: 0.85 }}>Capsule</div>
      <div style={{ opacity: 0.5, fontSize: 14, fontStyle: "italic" }}>
        Tap one to begin.
      </div>
      <Link
        href="/auth/sign-in?next=/dashboard"
        style={{
          marginTop: 8, fontSize: 13, opacity: 0.55,
          borderBottom: "0.5px solid rgba(255,255,255,0.25)",
          paddingBottom: 2,
        }}
      >
        Sign in
      </Link>
    </main>
  );
}
