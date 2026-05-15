"use client";

import { useRef } from "react";

interface Props {
  onFilesPicked: (files: File[]) => void;
}

// Persistent micro-affordance pill in the bottom-right. Always visible so
// owners and editors can discover the upload mechanism without us having to
// teach drag-and-drop. Tapping it opens the native file picker (the only
// way to "drop a file" on most mobile browsers).
//
// Non-writers can still see and click the pill; the upload itself is
// gated upstream by the CapsuleViewer.
export function DropPill({ onFilesPicked }: Props) {
  const inputRef = useRef<HTMLInputElement | null>(null);

  return (
    <>
      <button
        type="button"
        aria-label="Add a memory"
        onClick={() => inputRef.current?.click()}
        style={{
          position: "absolute",
          right: 18, bottom: 22, zIndex: 4,
          display: "inline-flex", alignItems: "center", gap: 8,
          padding: "8px 14px", height: 28,
          borderRadius: 999,
          background: "rgba(255,255,255,0.04)",
          border: "0.5px solid rgba(255,255,255,0.16)",
          color: "rgba(245,242,236,0.78)",
          fontSize: 12, letterSpacing: 0.4,
          cursor: "pointer",
          backdropFilter: "blur(14px)",
          WebkitBackdropFilter: "blur(14px)",
          transition: "transform 160ms ease, opacity 160ms ease, background 160ms ease",
        }}
        onMouseEnter={(e) => {
          e.currentTarget.style.transform = "scale(1.08)";
          e.currentTarget.style.background = "rgba(255,255,255,0.08)";
        }}
        onMouseLeave={(e) => {
          e.currentTarget.style.transform = "scale(1)";
          e.currentTarget.style.background = "rgba(255,255,255,0.04)";
        }}
      >
        <span aria-hidden style={{ fontSize: 13, opacity: 0.85 }}>+</span>
        <span>Drop anything</span>
      </button>
      <input
        ref={inputRef}
        type="file"
        accept="image/*,video/*,audio/*"
        multiple
        hidden
        onChange={(e) => {
          const files = Array.from(e.target.files ?? []);
          if (files.length) onFilesPicked(files);
          e.target.value = "";
        }}
      />
    </>
  );
}
