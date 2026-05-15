"use client";

import { useCallback, useEffect, useRef, useState } from "react";

export type DropPayload =
  | { kind: "file"; file: File }
  | { kind: "text"; text: string };

interface Options {
  enabled?: boolean;
  onAccept: (payload: DropPayload) => void;
  onUnsupportedFile?: (mime: string) => void;
}

interface DropzoneState {
  isDraggingOver: boolean;
}

// Window-level drag/drop + paste wiring. Pure event plumbing — does no
// uploads, no state mutation beyond the drag indicator. The caller decides
// what to do with each accepted payload (typical: optimistic memory then
// uploader.ts).
//
// Paste-as-text only fires when no input/textarea is focused so it doesn't
// fight with sign-in or comment fields.
export function useDropzone(opts: Options): DropzoneState {
  const { enabled = true, onAccept, onUnsupportedFile } = opts;
  const [isDraggingOver, setIsDraggingOver] = useState(false);

  // Refs let the listeners use the latest callbacks without re-binding
  // every render.
  const acceptRef = useRef(onAccept);
  const unsupportedRef = useRef(onUnsupportedFile);
  acceptRef.current = onAccept;
  unsupportedRef.current = onUnsupportedFile;

  // Drag-leave fires for child elements too. Track a depth counter so we
  // only flip isDraggingOver back to false when we leave the document.
  const dragDepth = useRef(0);

  const reset = useCallback(() => {
    dragDepth.current = 0;
    setIsDraggingOver(false);
  }, []);

  useEffect(() => {
    if (!enabled) { reset(); return; }

    const hasFiles = (e: DragEvent): boolean =>
      Array.from(e.dataTransfer?.types ?? []).includes("Files");

    const onEnter = (e: DragEvent) => {
      if (!hasFiles(e)) return;
      dragDepth.current += 1;
      setIsDraggingOver(true);
    };

    const onOver = (e: DragEvent) => {
      if (!hasFiles(e)) return;
      e.preventDefault();
      if (e.dataTransfer) e.dataTransfer.dropEffect = "copy";
    };

    const onLeave = (e: DragEvent) => {
      if (!hasFiles(e)) return;
      dragDepth.current = Math.max(0, dragDepth.current - 1);
      if (dragDepth.current === 0) setIsDraggingOver(false);
    };

    const onDrop = (e: DragEvent) => {
      if (!hasFiles(e)) return;
      e.preventDefault();
      reset();
      const files = Array.from(e.dataTransfer?.files ?? []);
      for (const file of files) {
        if (isAccepted(file.type)) acceptRef.current({ kind: "file", file });
        else unsupportedRef.current?.(file.type || "unknown");
      }
    };

    const onPaste = (e: ClipboardEvent) => {
      // Paste-as-text only when the focus is on body / a non-editable
      // element. Don't hijack inputs, textareas, contentEditable surfaces.
      const target = document.activeElement as HTMLElement | null;
      if (target && isEditable(target)) return;

      const text = e.clipboardData?.getData("text/plain")?.trim();
      if (!text) return;
      e.preventDefault();
      acceptRef.current({ kind: "text", text });
    };

    window.addEventListener("dragenter", onEnter);
    window.addEventListener("dragover", onOver);
    window.addEventListener("dragleave", onLeave);
    window.addEventListener("drop", onDrop);
    window.addEventListener("paste", onPaste);

    return () => {
      window.removeEventListener("dragenter", onEnter);
      window.removeEventListener("dragover", onOver);
      window.removeEventListener("dragleave", onLeave);
      window.removeEventListener("drop", onDrop);
      window.removeEventListener("paste", onPaste);
    };
  }, [enabled, reset]);

  return { isDraggingOver };
}

function isAccepted(mime: string): boolean {
  return mime.startsWith("image/") || mime.startsWith("video/") || mime.startsWith("audio/");
}

function isEditable(el: HTMLElement): boolean {
  const tag = el.tagName;
  if (tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT") return true;
  if (el.isContentEditable) return true;
  return false;
}
