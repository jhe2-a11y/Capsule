import { redirect } from "next/navigation";

import { serverClient } from "@/lib/supabase/server";
import type { CapsuleRow } from "@/lib/depthField/types";

import { CapsuleCard, type CapsuleCardData } from "./CapsuleCard";
import { EmptyState } from "./EmptyState";
import { SignOutButton } from "./SignOutButton";

export const dynamic = "force-dynamic";

export default async function DashboardPage() {
  const supabase = serverClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/auth/sign-in?next=/dashboard");
  }

  // RLS does the filtering: owners + collaborators on private capsules,
  // plus anything else SELECT-permitted by the policy. We narrow further by
  // requiring claimed_at so the dashboard never lists unclaimed seeded chips.
  const { data: capsuleRows } = await supabase
    .from("capsules")
    .select("*")
    .not("claimed_at", "is", null)
    .order("claimed_at", { ascending: false });

  const capsules = (capsuleRows ?? []) as CapsuleRow[];

  const cards: CapsuleCardData[] = await Promise.all(
    capsules.map(async (c) => {
      const { count } = await supabase
        .from("memories")
        .select("id", { count: "exact", head: true })
        .eq("capsule_id", c.id);

      const { data: seedRows } = await supabase
        .from("memories")
        .select("pos_x, pos_y")
        .eq("capsule_id", c.id)
        .order("created_at", { ascending: true })
        .limit(3);

      return {
        capsule: c,
        memoryCount: count ?? 0,
        seedPoints: (seedRows ?? []).map((r) => ({ x: r.pos_x, y: r.pos_y })),
        isOwner: c.owner_id === user.id,
      };
    }),
  );

  return (
    <main className="relative min-h-screen w-screen overflow-y-auto bg-vault">
      <header className="sticky top-0 z-10 flex items-center justify-between border-b border-hairline bg-vault/80 px-8 py-5 backdrop-blur">
        <div className="text-sm tracking-[0.2em] text-ink-dim">CAPSULE</div>
        <SignOutButton />
      </header>

      <section className="mx-auto w-full max-w-5xl px-6 py-12">
        <h1 className="mb-1 text-2xl font-normal tracking-wide text-ink">
          Your Capsules
        </h1>
        <p className="mb-10 text-sm italic text-ink-dim">
          {cards.length === 0
            ? "Nothing here yet."
            : cards.length === 1
              ? "One vessel."
              : `${cards.length} vessels.`}
        </p>

        {cards.length === 0 ? (
          <EmptyState />
        ) : (
          <div className="grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-3">
            {cards.map((card) => (
              <CapsuleCard key={card.capsule.id} data={card} />
            ))}
          </div>
        )}
      </section>
    </main>
  );
}
