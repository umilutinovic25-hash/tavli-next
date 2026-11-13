import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  buildUpstream,
  type GatewayRequest,
  limitResponse,
  mapUpstream,
  MAX_BODY_BYTES,
  parseRequest,
} from "./gateway.ts";

const valid = {
  provider: "groq",
  model: "openai/gpt-oss-120b",
  system: "sistem",
  prompt: "upit",
  images: [],
  temperature: 0.4,
};

function isError(r: unknown): r is { status: number; error: string } {
  return typeof r === "object" && r !== null && "error" in r;
}

Deno.test("prihvata ispravan tekstualni zahtev", () => {
  const r = parseRequest(valid, 200);
  assertEquals(isError(r), false);
  assertEquals((r as GatewayRequest).model, "openai/gpt-oss-120b");
});

Deno.test("odbija telo veće od 6 MiB sa 413 too_large", () => {
  assertEquals(parseRequest(valid, MAX_BODY_BYTES + 1), {
    status: 413,
    error: "too_large",
  });
});

Deno.test("odbija model van liste sa 400 bad_request", () => {
  assertEquals(parseRequest({ ...valid, model: "gpt-9" }, 200), {
    status: 400,
    error: "bad_request",
  });
});

Deno.test("odbija provajdera van liste i neslagan par provajder/model", () => {
  const bad = { status: 400, error: "bad_request" };
  assertEquals(parseRequest({ ...valid, provider: "evil" }, 200), bad);
  assertEquals(parseRequest({ ...valid, provider: "gemini" }, 200), bad);
});

Deno.test("odbija temperaturu van 0–2 i sliku sa nedozvoljenim tipom", () => {
  const bad = { status: 400, error: "bad_request" };
  assertEquals(parseRequest({ ...valid, temperature: 3 }, 200), bad);
  assertEquals(
    parseRequest({
      ...valid,
      provider: "openrouter",
      model: "google/gemma-3-27b-it:free",
      images: [{ mime: "text/html", base64: "AAAA" }],
    }, 200),
    bad,
  );
});

Deno.test("slika traži model koji podržava slike", () => {
  const r = parseRequest({
    ...valid,
    images: [{ mime: "image/jpeg", base64: "AAAA" }],
  }, 200);
  assertEquals(r, { status: 400, error: "bad_request" });
});

Deno.test("buildUpstream pravi isto telo kao OpenAICompatibleClient", () => {
  const req = parseRequest({
    ...valid,
    provider: "openrouter",
    model: "google/gemma-3-27b-it:free",
    images: [{ mime: "image/jpeg", base64: "AAAA" }],
  }, 200) as GatewayRequest;
  const { url, init } = buildUpstream(req, { openrouter: "k-or" });
  assertEquals(url, "https://openrouter.ai/api/v1/chat/completions");
  const headers = init.headers as Record<string, string>;
  assertEquals(headers["Authorization"], "Bearer k-or");
  assertEquals(headers["X-Title"], "Tavli");
  const body = JSON.parse(init.body as string);
  assertEquals(body.response_format, { type: "json_object" });
  assertEquals(body.messages[0], { role: "system", content: "sistem" });
  assertEquals(body.messages[1].content, [
    { type: "text", text: "upit" },
    { type: "image_url", image_url: { url: "data:image/jpeg;base64,AAAA" } },
  ]);
});

Deno.test("buildUpstream šalje običan tekst kad nema slika", () => {
  const req = parseRequest(valid, 200) as GatewayRequest;
  const { url, init } = buildUpstream(req, { groq: "k-g" });
  assertEquals(url, "https://api.groq.com/openai/v1/chat/completions");
  assertEquals(
    JSON.parse(init.body as string).messages[1],
    { role: "user", content: "upit" },
  );
});

const ok = (choices: unknown) =>
  new Response(JSON.stringify({ choices }), { status: 200 });

Deno.test("mapUpstream vraća tekst odgovora", async () => {
  const r = await mapUpstream(ok([{ message: { content: '{"a":1}' } }]));
  assertEquals(r, { status: 200, body: { text: '{"a":1}' } });
});

Deno.test("mapUpstream: prazan odgovor i ne-JSON su provider_error 502", async () => {
  const bad = { status: 502, body: { error: "provider_error" } };
  assertEquals(await mapUpstream(ok([])), bad);
  assertEquals(await mapUpstream(new Response("<html>", { status: 200 })), bad);
});

Deno.test("mapUpstream: 429 nosi retry_after i daily", async () => {
  const minute = await mapUpstream(
    new Response("{}", { status: 429, headers: { "retry-after": "12" } }),
  );
  assertEquals(minute, {
    status: 429,
    body: { error: "rate_limited", retry_after: 12, daily: false },
  });
  const daily = await mapUpstream(
    new Response("quota exceeded per day", { status: 429 }),
  );
  assertEquals(daily.body.daily, true);
});

Deno.test("mapUpstream: 401/403 su provider_error, 404 je model_not_found, 5xx provider_error", async () => {
  const providerError = { status: 502, body: { error: "provider_error" } };
  assertEquals(
    await mapUpstream(new Response("", { status: 401 })),
    providerError,
  );
  assertEquals(
    await mapUpstream(new Response("", { status: 403 })),
    providerError,
  );
  assertEquals(
    await mapUpstream(new Response("", { status: 500 })),
    providerError,
  );
  assertEquals(await mapUpstream(new Response("", { status: 404 })), {
    status: 404,
    body: { error: "model_not_found" },
  });
});

Deno.test("limitResponse: minutni limit kaže koliko do sledećeg minuta", () => {
  assertEquals(limitResponse("minute", new Date("2026-11-13T10:00:50Z")), {
    status: 429,
    body: { error: "rate_limited", daily: false, retry_after: 10 },
  });
});

Deno.test("limitResponse: dnevni limit je daily i kaže koliko do ponoći UTC", () => {
  assertEquals(limitResponse("day", new Date("2026-11-13T20:00:00Z")), {
    status: 429,
    body: { error: "rate_limited", daily: true, retry_after: 14400 },
  });
});
