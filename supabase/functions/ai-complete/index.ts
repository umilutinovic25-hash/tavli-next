import { createClient } from "npm:@supabase/supabase-js@2";
import {
  buildUpstream,
  type GatewayRequest,
  limitResponse,
  mapUpstream,
  MAX_BODY_BYTES,
  parseRequest,
} from "./gateway.ts";

const KEY_NAMES = {
  gemini: "GEMINI_API_KEY",
  groq: "GROQ_API_KEY",
  openrouter: "OPENROUTER_API_KEY",
} as const;

// Ništa iz tela zahteva (upit, slike) i nijedan ključ se ne loguje.
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
  if (Number(req.headers.get("content-length") ?? "0") > MAX_BODY_BYTES) {
    return json(413, { error: "too_large" });
  }
  if (!req.body) return json(400, { error: "bad_request" });
  const reader = req.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    size += value.length;
    if (size > MAX_BODY_BYTES) {
      await reader.cancel();
      return json(413, { error: "too_large" });
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const c of chunks) {
    bytes.set(c, offset);
    offset += c.length;
  }
  let raw: unknown;
  try {
    raw = JSON.parse(new TextDecoder().decode(bytes));
  } catch (_) {
    return json(400, { error: "bad_request" });
  }
  const parsed = parseRequest(raw, size);
  if ("error" in parsed) {
    return json(parsed.status, { error: parsed.error });
  }
  const request = parsed as GatewayRequest;
  const key = Deno.env.get(KEY_NAMES[request.provider]);
  if (!key) return json(503, { error: "unavailable" });
  // Ograničenje po nalogu pre poziva provajdera, a posle provere zahteva: ne
  // broje se pogrešni zahtevi. Ako brojač nije dostupan, zahtev se odbija.
  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );
  const { data: window, error: limitError } = await admin.rpc(
    "consume_ai_request",
    { uid: data.user.id },
  );
  if (limitError) return json(503, { error: "unavailable" });
  if (window === "minute" || window === "day") {
    const limited = limitResponse(window, new Date());
    return json(limited.status, limited.body);
  }
  if (window !== "ok") return json(503, { error: "unavailable" });
  try {
    const { url, init } = buildUpstream(request, { [request.provider]: key });
    const upstream = await fetch(url, {
      ...init,
      signal: AbortSignal.timeout(60_000),
    });
    const mapped = await mapUpstream(upstream);
    return json(mapped.status, mapped.body);
  } catch (_) {
    return json(502, { error: "provider_error" });
  }
});
