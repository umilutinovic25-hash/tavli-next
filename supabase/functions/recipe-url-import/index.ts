import { createClient } from "npm:@supabase/supabase-js@2";
import {
  concatBytes,
  extractRecipe,
  fetchPage,
  validateUrl,
} from "./import.ts";

Deno.serve(async (req: Request) => {
  const json = (status: number, body: Record<string, unknown>) =>
    Response.json(body, { status });
  if (req.method !== "POST") return json(405, { error: "method" });
  const token = (req.headers.get("Authorization") ?? "").replace(
    /^Bearer\s+/i,
    "",
  ).trim();
  if (!token) return json(401, { error: "unauthorized" });
  const client = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );
  const { data, error } = await client.auth.getUser(token);
  if (error || !data.user) return json(401, { error: "unauthorized" });
  // Ograničenje po nalogu (10/min, 60/dan) pre bilo kakvog mrežnog posla.
  // Ako brojač nije dostupan, funkcija odbija zahtev umesto da ga propusti.
  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );
  const { data: allowed, error: limitError } = await admin.rpc(
    "consume_recipe_import",
    { uid: data.user.id },
  );
  if (limitError) return json(503, { error: "unavailable" });
  if (allowed !== true) return json(429, { error: "rate_limited" });
  try {
    if (Number(req.headers.get("content-length") ?? "0") > 4096) {
      return json(400, { error: "url" });
    }
    if (!req.body) return json(400, { error: "url" });
    const reader = req.body.getReader();
    const chunks: Uint8Array[] = [];
    let size = 0;
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > 4096) {
        await reader.cancel();
        return json(400, { error: "url" });
      }
      chunks.push(value);
    }
    const body = JSON.parse(new TextDecoder().decode(concatBytes(chunks)));
    if (typeof body?.url !== "string") return json(400, { error: "url" });
    const url = validateUrl(body.url).toString();
    const recipe = extractRecipe(await fetchPage(url));
    return recipe
      ? json(200, { recipe, sourceUrl: url })
      : json(422, { error: "no_recipe" });
  } catch (_) {
    return json(400, { error: "fetch_failed" });
  }
});
