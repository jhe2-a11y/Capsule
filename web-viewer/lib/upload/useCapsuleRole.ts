"use client";

import { useEffect, useState } from "react";
import { browserClient } from "@/lib/supabase/client";

export type CapsuleRole = "owner" | "editor" | "viewer" | "anonymous";

export interface RoleState {
  loading: boolean;
  userId: string | null;
  role: CapsuleRole;
}

// Determines the current user's relationship to a capsule. Used by the
// drop zone to decide whether a drop becomes an upload or a "request
// access" prompt. Re-runs when auth state changes.
export function useCapsuleRole(capsuleId: string, ownerId: string | null): RoleState {
  const [state, setState] = useState<RoleState>({
    loading: true, userId: null, role: "anonymous",
  });

  useEffect(() => {
    const supabase = browserClient();
    let cancelled = false;

    const resolve = async () => {
      const { data: u } = await supabase.auth.getUser();
      const userId = u.user?.id ?? null;
      if (!userId) {
        if (!cancelled) setState({ loading: false, userId: null, role: "anonymous" });
        return;
      }
      if (ownerId && userId === ownerId) {
        if (!cancelled) setState({ loading: false, userId, role: "owner" });
        return;
      }
      const { data: collab } = await supabase
        .from("capsule_collaborators")
        .select("role")
        .eq("capsule_id", capsuleId)
        .eq("user_id", userId)
        .maybeSingle();

      if (cancelled) return;
      const role: CapsuleRole = collab?.role === "editor" || collab?.role === "owner"
        ? "editor"
        : "viewer";
      setState({ loading: false, userId, role });
    };

    void resolve();

    const { data: sub } = supabase.auth.onAuthStateChange(() => {
      void resolve();
    });

    return () => { cancelled = true; sub.subscription.unsubscribe(); };
  }, [capsuleId, ownerId]);

  return state;
}

export function canWrite(role: CapsuleRole): boolean {
  return role === "owner" || role === "editor";
}
