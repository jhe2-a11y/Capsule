import Link from "next/link";

import type { CapsuleRow } from "@/lib/depthField/types";
import { relativeTime } from "@/lib/format/relativeTime";
import { Card, CardContent, CardDescription, CardTitle } from "@/components/ui/card";
import { cn } from "@/lib/utils";

export interface CapsuleCardData {
  capsule: CapsuleRow;
  memoryCount: number;
  seedPoints: Array<{ x: number; y: number }>;
  isOwner: boolean;
}

export function CapsuleCard({ data }: { data: CapsuleCardData }) {
  const { capsule, memoryCount, seedPoints, isOwner } = data;
  const title = capsule.title?.trim() || "Unnamed Capsule";
  const claimed = capsule.claimed_at
    ? `claimed ${relativeTime(capsule.claimed_at)}`
    : "unclaimed";
  const memoriesLabel =
    memoryCount === 0
      ? "no memories yet"
      : `${memoryCount} ${memoryCount === 1 ? "memory" : "memories"}`;

  return (
    <Link
      href={`/c/${capsule.id}`}
      className="group block focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/40 rounded-lg"
      aria-label={`Open ${title}`}
    >
      <Card className="overflow-hidden transition-colors group-hover:bg-white/[0.04]">
        <Thumbnail seedPoints={seedPoints} />
        <CardContent className="pt-4">
          <div className="flex items-start justify-between gap-3">
            <CardTitle className="line-clamp-1">{title}</CardTitle>
            <span
              className={cn(
                "shrink-0 rounded-full border px-2 py-0.5 text-[10px] uppercase tracking-wider",
                isOwner
                  ? "border-white/20 text-ink-dim"
                  : "border-white/10 text-ink-faint",
              )}
            >
              {isOwner ? "Owner" : "Editor"}
            </span>
          </div>
          <CardDescription className="mt-1">
            {memoriesLabel} · {claimed}
          </CardDescription>
        </CardContent>
      </Card>
    </Link>
  );
}

function Thumbnail({ seedPoints }: { seedPoints: Array<{ x: number; y: number }> }) {
  // A CSS-only "glow" thumbnail. Dots correspond to the first few memories'
  // positions, normalized from [-1,1] to [10%, 90%] in the container. Cheap,
  // no Three.js per card.
  return (
    <div
      aria-hidden
      className="relative h-28 w-full overflow-hidden bg-[radial-gradient(ellipse_at_50%_60%,rgba(255,255,255,0.10),rgba(10,10,15,0)_60%)]"
    >
      <div className="absolute inset-0 bg-[radial-gradient(circle_at_30%_30%,rgba(180,180,255,0.05),transparent_40%),radial-gradient(circle_at_70%_70%,rgba(255,220,180,0.04),transparent_45%)]" />
      {seedPoints.slice(0, 3).map((p, i) => {
        const left = `${((p.x + 1) / 2) * 80 + 10}%`;
        const top = `${((1 - p.y) / 2) * 80 + 10}%`;
        return (
          <span
            key={i}
            className="absolute h-1.5 w-1.5 -translate-x-1/2 -translate-y-1/2 rounded-full bg-white/70 shadow-[0_0_8px_rgba(255,255,255,0.6)] animate-soft-pulse"
            style={{ left, top, animationDelay: `${i * 0.4}s` }}
          />
        );
      })}
    </div>
  );
}
