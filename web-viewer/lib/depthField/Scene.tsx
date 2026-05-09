"use client";

import { Canvas, useFrame, useLoader, useThree } from "@react-three/fiber";
import { Suspense, useEffect, useMemo, useRef, useState } from "react";
import * as THREE from "three";
import { TextureLoader } from "three";
import type { MemoryRow } from "./types";

// Web parity for the iOS depth field. Memories live in normalized capsule
// space (x,y in [-1,1], z in [0,1]). Camera sits at z = 1.2; pull-forward is
// implemented as a smooth dolly along z.

interface SceneProps {
  memories: MemoryRow[];
  resolveURL: (memoryId: string) => Promise<string | null>;
}

export function DepthFieldScene({ memories, resolveURL }: SceneProps) {
  const [focused, setFocused] = useState<string | null>(null);

  return (
    <Canvas
      gl={{ antialias: true, alpha: false }}
      camera={{ position: [0, 0, 2.4], fov: 38 }}
      dpr={[1, 2]}
      style={{ background: "linear-gradient(180deg,#0a0a0f 0%,#1a1018 100%)" }}
      onPointerMissed={() => setFocused(null)}
    >
      <ambientLight intensity={0.5} />
      <directionalLight position={[3, 4, 5]} intensity={0.6} />
      <Suspense fallback={null}>
        <Field memories={memories} focused={focused} setFocused={setFocused} resolveURL={resolveURL} />
      </Suspense>
      <Parallax />
    </Canvas>
  );
}

function Field({
  memories, focused, setFocused, resolveURL,
}: {
  memories: MemoryRow[];
  focused: string | null;
  setFocused: (id: string | null) => void;
  resolveURL: SceneProps["resolveURL"];
}) {
  const group = useRef<THREE.Group>(null);
  const { camera } = useThree();

  // Dolly camera toward focused node along z.
  useFrame((_, delta) => {
    const target = focused
      ? clamp(memberZ(memories, focused) + 0.55, 1.0, 2.2)
      : 2.4;
    camera.position.z += (target - camera.position.z) * Math.min(1, delta * 4);
  });

  return (
    <group ref={group}>
      {memories.map((m) => (
        <MemoryQuad
          key={m.id}
          memory={m}
          focused={focused === m.id}
          dim={focused !== null && focused !== m.id}
          onClick={() => setFocused(focused === m.id ? null : m.id)}
          resolveURL={resolveURL}
        />
      ))}
    </group>
  );
}

function MemoryQuad({
  memory, focused, dim, onClick, resolveURL,
}: {
  memory: MemoryRow;
  focused: boolean;
  dim: boolean;
  onClick: () => void;
  resolveURL: SceneProps["resolveURL"];
}) {
  const ref = useRef<THREE.Mesh>(null);
  const [url, setUrl] = useState<string | null>(null);

  useEffect(() => {
    let live = true;
    if (memory.kind !== "text") {
      resolveURL(memory.id).then((u) => { if (live) setUrl(u); });
    }
    return () => { live = false; };
  }, [memory.id, memory.kind, resolveURL]);

  useFrame((_, delta) => {
    if (!ref.current) return;
    const target = focused ? 1.18 : (dim ? 0.82 : 1);
    ref.current.scale.x += (target - ref.current.scale.x) * Math.min(1, delta * 5);
    ref.current.scale.y = ref.current.scale.x;
    const op = (ref.current.material as THREE.MeshBasicMaterial).opacity;
    const targetOp = dim ? 0.45 : 1.0;
    (ref.current.material as THREE.MeshBasicMaterial).opacity =
      op + (targetOp - op) * Math.min(1, delta * 5);
  });

  return (
    <mesh
      ref={ref}
      position={[memory.pos_x, memory.pos_y, memory.pos_z * 0.6]}
      onClick={(e) => { e.stopPropagation(); onClick(); }}
    >
      <planeGeometry args={[0.42, 0.52]} />
      <meshBasicMaterial
        transparent
        toneMapped={false}
        opacity={1}
        side={THREE.DoubleSide}
      >
        <QuadTexture memory={memory} url={url} />
      </meshBasicMaterial>
    </mesh>
  );
}

function QuadTexture({ memory, url }: { memory: MemoryRow; url: string | null }) {
  if (memory.kind === "text") {
    return <TextMap text={memory.text_content ?? ""} />;
  }
  if (!url) {
    return <PlaceholderMap />;
  }
  // video and voice both render a poster on the field; full playback occurs
  // in the foreground HTML overlay (see page.tsx).
  return <ImageMap url={url} />;
}

function TextMap({ text }: { text: string }) {
  const tex = useTextTexture(text);
  return <primitive attach="map" object={tex} />;
}

function PlaceholderMap() {
  const tex = usePlaceholderTexture();
  return <primitive attach="map" object={tex} />;
}

function ImageMap({ url }: { url: string }) {
  const tex = useLoader(TextureLoader, url);
  tex.colorSpace = THREE.SRGBColorSpace;
  return <primitive attach="map" object={tex} />;
}

function useTextTexture(text: string): THREE.CanvasTexture {
  return useMemo(() => {
    const canvas = document.createElement("canvas");
    canvas.width = 512; canvas.height = 640;
    const ctx = canvas.getContext("2d")!;
    ctx.fillStyle = "rgba(20,18,22,1)";
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.fillStyle = "rgba(245,242,236,0.92)";
    ctx.font = "28px 'New York', Georgia, serif";
    wrap(ctx, text || "…", 36, 70, canvas.width - 72, 38);
    const tex = new THREE.CanvasTexture(canvas);
    tex.colorSpace = THREE.SRGBColorSpace;
    return tex;
  }, [text]);
}

function usePlaceholderTexture(): THREE.CanvasTexture {
  return useMemo(() => {
    const c = document.createElement("canvas");
    c.width = 4; c.height = 4;
    const ctx = c.getContext("2d")!;
    ctx.fillStyle = "rgba(220,210,195,0.5)";
    ctx.fillRect(0, 0, 4, 4);
    return new THREE.CanvasTexture(c);
  }, []);
}

function wrap(ctx: CanvasRenderingContext2D, text: string, x: number, y: number, maxWidth: number, lineHeight: number) {
  const words = text.split(/\s+/);
  let line = "";
  for (const w of words) {
    const test = line ? `${line} ${w}` : w;
    if (ctx.measureText(test).width > maxWidth) {
      ctx.fillText(line, x, y);
      line = w;
      y += lineHeight;
    } else line = test;
  }
  if (line) ctx.fillText(line, x, y);
}

function memberZ(list: MemoryRow[], id: string): number {
  return list.find((m) => m.id === id)?.pos_z ?? 0.5;
}

function clamp(n: number, lo: number, hi: number): number {
  return Math.min(hi, Math.max(lo, n));
}

function Parallax() {
  const { camera } = useThree();
  useEffect(() => {
    const onMove = (e: PointerEvent) => {
      const x = (e.clientX / window.innerWidth - 0.5) * 0.18;
      const y = (e.clientY / window.innerHeight - 0.5) * -0.18;
      camera.position.x += (x - camera.position.x) * 0.06;
      camera.position.y += (y - camera.position.y) * 0.06;
      camera.lookAt(0, 0, 0);
    };
    window.addEventListener("pointermove", onMove);
    return () => window.removeEventListener("pointermove", onMove);
  }, [camera]);
  return null;
}
