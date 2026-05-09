"use client";

import { useEffect, useRef, useState } from "react";
import type { MemoryRow } from "./types";

// Fullscreen overlay shown when a memory is "pulled forward". The Metal/WebGL
// field stays visible behind the dim layer; this component handles the
// per-kind foregrounded experience (kind-tinted serif text, Ken Burns photo,
// looping muted video, breathing voice waveform).

interface Props {
  memory: MemoryRow;
  resolveURL: (memoryId: string) => Promise<string | null>;
  onDismiss: () => void;
}

export function Foreground({ memory, resolveURL, onDismiss }: Props) {
  const [url, setUrl] = useState<string | null>(null);

  useEffect(() => {
    if (memory.kind === "text") return;
    let live = true;
    resolveURL(memory.id).then((u) => { if (live) setUrl(u); });
    return () => { live = false; };
  }, [memory.id, memory.kind, resolveURL]);

  return (
    <div
      role="dialog"
      aria-modal
      onClick={onDismiss}
      style={{
        position: "fixed", inset: 0, zIndex: 5,
        background: "rgba(8, 6, 12, 0.55)",
        backdropFilter: "blur(18px)",
        WebkitBackdropFilter: "blur(18px)",
        display: "flex", alignItems: "center", justifyContent: "center",
        animation: "capsule-fade-in 0.45s ease",
      }}
    >
      <div onClick={(e) => e.stopPropagation()} style={{
        maxWidth: "min(720px, 92vw)", maxHeight: "92vh",
        width: "100%", display: "flex",
        alignItems: "center", justifyContent: "center",
      }}>
        <Body memory={memory} url={url} />
      </div>

      <style>{`
        @keyframes capsule-fade-in {
          from { opacity: 0; }
          to   { opacity: 1; }
        }
      `}</style>
    </div>
  );
}

function Body({ memory, url }: { memory: MemoryRow; url: string | null }) {
  switch (memory.kind) {
    case "text":  return <TextBody text={memory.text_content ?? ""} />;
    case "photo": return <PhotoBody url={url} />;
    case "video": return <VideoBody url={url} />;
    case "voice": return <VoiceBody url={url} />;
  }
}

function TextBody({ text }: { text: string }) {
  return (
    <div style={{
      fontFamily: '"New York", Georgia, serif',
      fontSize: "clamp(18px, 2.4vw, 26px)",
      lineHeight: 1.55, color: "rgba(245,242,236,0.94)",
      padding: "48px 28px",
      textAlign: "left",
      whiteSpace: "pre-wrap",
      overflowY: "auto", maxHeight: "84vh",
    }}>
      {text}
    </div>
  );
}

function PhotoBody({ url }: { url: string | null }) {
  if (!url) return <Materializing />;
  return (
    <img
      src={url}
      alt=""
      style={{
        maxWidth: "100%", maxHeight: "84vh", objectFit: "contain",
        borderRadius: 4, animation: "capsule-kenburns 14s ease-in-out infinite alternate",
      }}
    />
  );
}

function VideoBody({ url }: { url: string | null }) {
  if (!url) return <Materializing />;
  return (
    <video
      src={url}
      autoPlay loop muted playsInline
      style={{ maxWidth: "100%", maxHeight: "84vh", borderRadius: 4 }}
    />
  );
}

function VoiceBody({ url }: { url: string | null }) {
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const [playing, setPlaying] = useState(false);

  useEffect(() => {
    if (!url) return;
    const a = new Audio(url);
    audioRef.current = a;
    a.play().then(() => setPlaying(true)).catch(() => setPlaying(false));
    a.addEventListener("ended", () => setPlaying(false));
    return () => { a.pause(); audioRef.current = null; };
  }, [url]);

  return (
    <div style={{
      width: 280, height: 280, position: "relative",
      display: "flex", alignItems: "center", justifyContent: "center",
    }}>
      {[0, 1, 2].map((i) => (
        <div key={i} style={{
          position: "absolute",
          width: 140 + i * 36, height: 140 + i * 36,
          borderRadius: "50%",
          border: "0.5px solid rgba(255,255,255,0.14)",
          animation: playing
            ? `capsule-breathe ${2 + i * 0.4}s ease-in-out infinite`
            : "none",
        }} />
      ))}
      <button
        onClick={() => {
          const a = audioRef.current; if (!a) return;
          if (a.paused) { a.play(); setPlaying(true); }
          else          { a.pause(); setPlaying(false); }
        }}
        style={{
          width: 96, height: 96, borderRadius: "50%",
          background: "rgba(255,255,255,0.06)",
          border: "0.5px solid rgba(255,255,255,0.18)",
          color: "rgba(245,242,236,0.92)",
          fontSize: 22, cursor: "pointer",
        }}
      >
        {playing ? "❙❙" : "▶"}
      </button>
      <style>{`
        @keyframes capsule-breathe {
          0%, 100% { transform: scale(1); opacity: 0.6; }
          50%      { transform: scale(1.06); opacity: 1; }
        }
        @keyframes capsule-kenburns {
          0%   { transform: scale(1.04) translate(-1%, 1%); }
          100% { transform: scale(1.10) translate(2%, -2%); }
        }
      `}</style>
    </div>
  );
}

function Materializing() {
  return (
    <div style={{
      width: 220, height: 220, borderRadius: "50%",
      background: "radial-gradient(circle, rgba(255,255,255,0.10), transparent 60%)",
      filter: "blur(28px)",
    }} />
  );
}
