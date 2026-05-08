export type MemoryKind = "photo" | "video" | "voice" | "text";

export interface CapsuleRow {
  id: string;
  owner_id: string | null;
  access_mode: "open" | "private";
  title: string | null;
  claimed_at: string | null;
  created_at: string;
}

export interface MemoryRow {
  id: string;
  capsule_id: string;
  kind: MemoryKind;
  storage_path: string | null;
  text_content: string | null;
  duration_ms: number | null;
  pos_x: number;
  pos_y: number;
  pos_z: number;
  created_at: string;
  created_by: string | null;
}
