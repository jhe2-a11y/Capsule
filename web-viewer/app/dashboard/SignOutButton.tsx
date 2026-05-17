"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

import { browserClient } from "@/lib/supabase/client";
import { Button } from "@/components/ui/button";

export function SignOutButton() {
  const router = useRouter();
  const [working, setWorking] = useState(false);

  async function signOut() {
    if (working) return;
    setWorking(true);
    const supabase = browserClient();
    await supabase.auth.signOut();
    router.replace("/");
    router.refresh();
  }

  return (
    <Button
      variant="ghost"
      size="sm"
      onClick={signOut}
      disabled={working}
      aria-label="Sign out"
    >
      {working ? "…" : "Sign out"}
    </Button>
  );
}
