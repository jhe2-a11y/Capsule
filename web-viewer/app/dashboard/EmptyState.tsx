export function EmptyState() {
  return (
    <div className="mx-auto flex max-w-md flex-col items-center gap-4 py-16 text-center animate-fade-in">
      <div
        aria-hidden
        className="h-24 w-24 rounded-full border border-hairline bg-[radial-gradient(circle_at_center,rgba(255,255,255,0.08),transparent_70%)]"
      />
      <div className="text-lg tracking-wide">No Capsules yet</div>
      <p className="text-sm italic text-ink-dim">
        Tap a Capsule chip with your phone to claim it. The first tap makes it
        yours.
      </p>
    </div>
  );
}
