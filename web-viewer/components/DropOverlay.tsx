"use client";

import { useState } from "react";

interface Props {
  visible: boolean;
  canWrite: boolean;
  // Called only when canWrite is false and the user clicks "Request access".
  // Resolves to true on success so the overlay can show confirmation.
  onRequestAccess?: () => Promise<boolean>;
}

// Soft overlay shown while a file is being dragged over the window. Two
// variants: writers see "Release to add"; non-writers see a polite
// request-access prompt.
export function DropOverlay({ visible, canWrite, onRequestAccess }: Props) {
  const [requestState, setRequestState] = useState<"idle" | "sending" | "sent" | "failed">("idle");

  if (!visible && requestState === "idle") return null;

  const handleRequest = async () => {
    if (!onRequestAccess || requestState !== "idle") return;
    setRequestState("sending");
    const ok = await onRequestAccess();
    setRequestState(ok ? "sent" : "failed");
    // The hover overlay only persists while a drag is in progress; the
    // success/failure state will be reset by the parent when the next drag
    // begins. For non-drag flows (e.g., click on pill while denied) the
    // parent can choose to show this via a separate path.
  };

  return (
    <div
      role="status"
      aria-live="polite"
      style={{
        position: "fixed", inset: 0, zIndex: 6,
        background: "rgba(8, 6, 12, 0.45)",
        backdropFilter: "blur(20px)",
        WebkitBackdropFilter: "blur(20px)",
        display: "flex", alignItems: "center", justifyContent: "center",
        pointerEvents: canWrite ? "none" : "auto",
        animation: "capsule-overlay-fade 0.25s ease",
      }}
    >
      <div style={{
        display: "flex", flexDirection: "column",
        alignItems: "center", gap: 14, textAlign: "center",
        padding: "32px 40px",
        maxWidth: 360,
      }}>
        <div aria-hidden style={{
          width: 84, height: 84, borderRadius: "50%",
          border: "0.5px solid rgba(255,255,255,0.22)",
          animation: "capsule-overlay-pulse 1.8s ease-in-out infinite",
        }} />
        {canWrite ? (
          <>
            <div style={{ fontSize: 19 }}>Release to add to this Capsule</div>
            <div style={{ fontSize: 13, opacity: 0.6, fontStyle: "italic" }}>
              Photos, videos, voice memos
            </div>
          </>
        ) : (
          <>
            <div style={{ fontSize: 19 }}>
              {requestState === "sent"
                ? "Request sent."
                : "You don’t have edit access to this Capsule."}
            </div>
            {requestState !== "sent" && (
              <div style={{ fontSize: 13, opacity: 0.6, fontStyle: "italic" }}>
                Ask the owner to invite you, or request access here.
              </div>
            )}
            {requestState !== "sent" && (
              <button
                type="button"
                onClick={handleRequest}
                disabled={requestState === "sending"}
                style={{
                  marginTop: 8, padding: "10px 22px", borderRadius: 999,
                  background: "rgba(255,255,255,0.92)", color: "#000",
                  fontSize: 14, cursor: requestState === "sending" ? "default" : "pointer",
                  opacity: requestState === "sending" ? 0.6 : 1,
                  border: "none",
                }}
              >
                {requestState === "sending" ? "Sending…" : "Request access"}
              </button>
            )}
            {requestState === "failed" && (
              <div style={{ fontSize: 12, opacity: 0.55 }}>
                Couldn’t send right now. Try again in a moment.
              </div>
            )}
          </>
        )}
      </div>
      <style>{`
        @keyframes capsule-overlay-fade {
          from { opacity: 0; }
          to   { opacity: 1; }
        }
        @keyframes capsule-overlay-pulse {
          0%, 100% { transform: scale(1); opacity: 0.7; }
          50%      { transform: scale(1.08); opacity: 1; }
        }
      `}</style>
    </div>
  );
}
