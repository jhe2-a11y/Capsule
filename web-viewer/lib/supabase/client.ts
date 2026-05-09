import {
  createBrowserClient,
  createServerClient,
  type CookieOptions,
} from "@supabase/ssr";
import { cookies } from "next/headers";

export function browserClient() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
  );
}

export function serverClient() {
  const store = cookies();
  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return store.getAll();
        },
        setAll(items: { name: string; value: string; options?: CookieOptions }[]) {
          // In RSC contexts cookies() is read-only; setAll is invoked by the
          // SSR helper during refresh and is a no-op there. Wrapping in
          // try/catch lets the same factory work for both pages and route
          // handlers without splitting into two clients.
          try {
            for (const { name, value, options } of items) {
              (store as unknown as { set: (n: string, v: string, o?: unknown) => void })
                .set(name, value, options);
            }
          } catch {
            // intentionally ignored
          }
        },
      },
    },
  );
}
