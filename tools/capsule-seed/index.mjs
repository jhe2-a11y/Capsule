#!/usr/bin/env node
// capsule-seed — mint N unclaimed capsules and print one Universal Link per
// row. Pipe the output into the chip-encoder fixture; each line corresponds
// to one physical chip.
//
//   SUPABASE_URL=…  SUPABASE_SERVICE_ROLE_KEY=…  \
//     ./index.mjs --count 100 --host capsule.app
//
// `claimed_at` is left null. A capsule becomes ownable on first authenticated
// tap (see public.claim_capsule).

import { randomUUID } from "node:crypto";
import { parseArgs } from "node:util";

const { values } = parseArgs({
  options: {
    count: { type: "string", default: "1" },
    host:  { type: "string", default: "capsule.app" },
    "access-mode": { type: "string", default: "open" },
    "dry-run": { type: "boolean", default: false },
  },
});

const count = Math.max(1, parseInt(values.count, 10) || 1);
const host  = values.host;
const accessMode = values["access-mode"];
const dryRun = values["dry-run"];

if (!["open", "private"].includes(accessMode)) {
  console.error(`access-mode must be 'open' or 'private', got '${accessMode}'`);
  process.exit(2);
}

const url = process.env.SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!url || !key) {
  console.error("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required.");
  process.exit(2);
}

const rows = Array.from({ length: count }, () => ({
  id: randomUUID(),
  access_mode: accessMode,
}));

if (dryRun) {
  for (const row of rows) {
    process.stdout.write(`https://${host}/c/${row.id}\n`);
  }
  console.error(`(dry-run) ${count} URLs printed; nothing inserted.`);
  process.exit(0);
}

const { createClient } = await import("@supabase/supabase-js");
const supabase = createClient(url, key, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const { error } = await supabase.from("capsules").insert(rows);
if (error) {
  console.error("insert failed:", error.message);
  process.exit(1);
}

for (const row of rows) {
  process.stdout.write(`https://${host}/c/${row.id}\n`);
}
console.error(`seeded ${count} capsules (access_mode=${accessMode}).`);
