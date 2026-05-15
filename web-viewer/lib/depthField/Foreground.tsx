"use client";

import { useEffect, useRef, useState } from "react";
import type { MemoryRow } from "./types";
import { relativeTime, formatDuration } from "@/lib/format/relativeTime";

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
  const [resolveError, setResolveError] = useState(false);

  useEffect(() => {
    if (memory.kind === "text") return;
    setUrl(null);
    setResolveError(false);
    let live = true;
    resolveURL(memory.id).then((u) => {
      if (!live) return;
      if (u) setUrl(u);
      else setResolveError(true);
    });
    return () => { live = false; };
  }, [memory.id, memory.kind, resolveURL]);

  const kindLabel = labelFor(memory.kind);

  return (
    <div
      role="dialog"
      aria-modal
      aria-label={`${kindLabel} memory, added ${relativeTime(memory.created_at)}`}
      onClick={onDismiss}
      style={{
        position: "fixed", inset: 0, zIndex: 5,
        background: "rgba(8, 6, 12, 0.55)",
        backdropFilter: "blur(18px)",
        WebkitBackdropFilter: "blur(18px)",
        display: "flex", flexDirection: "column",
        alignItems: "center", justifyContent: "center",
        animation: "capsule-fade-in 0.45s ease",
      }}
    >
      <div onClick={(e) => e.stopPropagation()} style={{
        maxWidth: "min(720px, 92vw)", maxHeight: "84vh",
        width: "100%", display: "flex",
        alignItems: "center", justifyContent: "center",
      }}>
        {resolveError
          ? <BodyError kind={memory.kind} />
          : <Body memory={memory} url={url} />}
      </div>

      <MetadataStrip memory={memory} />

      <style>{`
        @keyframes capsule-fade-in {
          from { opacity: 0; }
          to   { opacity: 1; }
        }
      `}</style>
    </div>
  );
}

function MetadataStrip({ memory }: { memory: MemoryRow }) {
  return (
    <div style={{
      marginTop: 24,
      fontSize: 13, letterSpacing: 0.5,
      opacity: 0.55, fontStyle: "italic",
      textAlign: "center",
    }}>
      {labelFor(memory.kind)} · {relativeTime(memory.created_at)}
    </div>
  );
}

function labelFor(kind: MemoryRow["kind"]): string {
  switch (kind) {
    case "text":  return "Note";
    case "photo": return "Photo";
    case "video": return "Video";
    case "voice": return "Voice";
  }
}

function Body({ memory, url }: { memory: MemoryRow; url: string | null }) {
  switch (memory.kind) {
    case "text":  return <TextBody text={memory.text_content ?? ""} />;
    case "photo": return <PhotoBody url={url} />;
    case "video": return <VideoBody url={url} />;
    case "voice": return <VoiceBody url={url} durationMs={memory.duration_ms} />;
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
      overflowY: "auto", maxHeight: "72vh",
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
        maxWidth: "100%", maxHeight: "72vh", objectFit: "contain",
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
      style={{ maxWidth: "100%", maxHeight: "72vh", borderRadius: 4 }}
    />
  );
}

function VoiceBody({ url, durationMs }: { url: string | null; durationMs: number | null }) {
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const [playing, setPlaying] = useState(false);
  const [currentMs, setCurrentMs] = useState(0);
  const [totalMs, setTotalMs] = useState<number>(durationMs ?? 0);

  useEffect(() => {
    if (!url) return;
    const a = new Audio(url);
    audioRef.current = a;

    const onTime  = () => setCurrentMs(Math.round((a.currentTime || 0) * 1000));
    const onMeta  = () => {
      const ms = Math.round((a.duration || 0) * 1000);
      if (Number.isFinite(ms) && ms > 0) setTotalMs(ms);
    };
    const onEnded = () => { setPlaying(false); setCurrentMs(0); };

    a.addEventListener("timeupdate", onTime);
    a.addEventListener("loadedmetadata", onMeta);
    a.addEventListener("ended", onEnded);

    a.play().then(() => setPlaying(true)).catch(() => setPlaying(false));

    return () => {
      a.pause();
      a.removeEventListener("timeupdate", onTime);
      a.removeEventListener("loadedmetadata", onMeta);
      a.removeEventListener("ended", onEnded);
      audioRef.current = null;
    };
  }, [url]);

  const togglePlay = () => {
    const a = audioRef.current; if (!a) return;
    if (a.paused) { a.play(); setPlaying(true); }
    else          { a.pause(); setPlaying(false); }
  };

  const onScrub = (e: React.MouseEvent<HTMLDivElement>) => {
    const a = audioRef.current; if (!a || !totalMs) return;
    const rect = e.currentTarget.getBoundingClientRect();
    const ratio = clamp((e.clientX - rect.left) / rect.width, 0, 1);
    a.currentTime = (totalMs / 1000) * ratio;
    setCurrentMs(Math.round(totalMs * ratio));
  };

  const progress = totalMs > 0 ? clamp(currentMs / totalMs, 0, 1) : 0;

  return (
    <div style={{
      display: "flex", flexDirection: "column",
      alignItems: "center", gap: 18,
    }}>
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
          onClick={togglePlay}
          aria-label={playing ? "Pause voice memory" : "Play voice memory"}
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
      </div>

      <div style={{
        width: "min(280px, 70vw)",
        display: "flex", flexDirection: "column", gap: 6,
      }}>
        <div
          role="slider"
          aria-label="Audio progress"
          aria-valuemin={0}
          aria-valuemax={Math.max(totalMs, 1)}
          aria-valuenow={currentMs}
          onClick={onScrub}
          style={{
            height: 3, width: "100%",
            background: "rgba(255,255,255,0.12)",
            borderRadius: 999, cursor: totalMs > 0 ? "pointer" : "default",
            position: "relative",
          }}
        >
          <div style={{
            position: "absolute", inset: 0, width: `${progress * 100}%`,
            background: "rgba(245,242,236,0.7)", borderRadius: 999,
          }} />
        </div>
        <div style={{
          display: "flex", justifyContent: "space-between",
          fontSize: 11, opacity: 0.55, fontVariantNumeric: "tabular-nums",
        }}>
          <span>{formatDuration(currentMs)}</span>
          <span>{formatDuration(totalMs)}</span>
        </div>
      </div>

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
    <div
      aria-label="Loading"
      style={{
        width: 220, height: 220, borderRadius: "50%",
        background: "radial-gradient(circle, rgba(255,255,255,0.10), transparent 60%)",
        filter: "blur(28px)",
        animation: "capsule-pulse 2.4s ease-in-out infinite",
      }}
    >
      <style>{`
        @keyframes capsule-pulse {
          0%, 100% { opacity: 0.6; }
          50%      { opacity: 1; }
        }
      `}</style>
    </div>
  );
}

function BodyError({ kind }: { kind: MemoryRow["kind"] }) {
  return (
    <div style={{
      display: "flex", flexDirection: "column",
      alignItems: "center", gap: 10, opacity: 0.75,
      textAlign: "center", padding: 24,
    }}>
      <div style={{
        width: 64, height: 64, borderRadius: "50%",
        border: "0.5px solid rgba(255,255,255,0.2)",
      }} />
      <div style={{ fontSize: 17 }}>This {labelFor(kind).toLowerCase()} couldn’t load.</div>
      <div style={{ fontSize: 13, opacity: 0.6, fontStyle: "italic" }}>
        Close this view and try again in a moment.
      </div>
    </div>
  );
}

function clamp(n: number, lo: number, hi: number): number {
  return Math.min(hi, Math.max(lo, n));
}
