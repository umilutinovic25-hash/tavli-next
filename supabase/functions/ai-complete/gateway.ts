// Čista logika AI gatewaya: provera zahteva, pravljenje zahteva ka provajderu
// i mapiranje odgovora. Bez mreže, da se testira bez lažnog fetch-a.

export const MAX_BODY_BYTES = 6 * 1024 * 1024;

export type Provider = "gemini" | "groq" | "openrouter";
export type GatewayImage = { mime: string; base64: string };
export type GatewayRequest = {
  provider: Provider;
  model: string;
  system: string;
  prompt: string;
  images: GatewayImage[];
  temperature: number;
};
export type GatewayError = { status: number; error: string };

const BASE_URL: Record<Provider, string> = {
  gemini: "https://generativelanguage.googleapis.com/v1beta/openai/",
  groq: "https://api.groq.com/openai/v1/",
  openrouter: "https://openrouter.ai/api/v1/",
};

// Održava se uz lib/ai/chain_config.dart: samo ovi modeli se prosleđuju.
const MODELS: Record<string, { provider: Provider; vision: boolean }> = {
  "gemini-pro-latest": { provider: "gemini", vision: true },
  "gemini-flash-latest": { provider: "gemini", vision: true },
  "gemini-flash-lite-latest": { provider: "gemini", vision: true },
  "meta-llama/llama-4-maverick-17b-128e-instruct": {
    provider: "groq",
    vision: true,
  },
  "openai/gpt-oss-120b": { provider: "groq", vision: false },
  "llama-3.3-70b-versatile": { provider: "groq", vision: false },
  "google/gemma-3-27b-it:free": { provider: "openrouter", vision: true },
};

const IMAGE_MIMES = new Set(["image/jpeg", "image/png", "image/webp"]);
const BAD_REQUEST: GatewayError = { status: 400, error: "bad_request" };

export function parseRequest(
  raw: unknown,
  byteLength: number,
): GatewayRequest | GatewayError {
  if (byteLength > MAX_BODY_BYTES) return { status: 413, error: "too_large" };
  if (typeof raw !== "object" || raw === null) return BAD_REQUEST;
  const r = raw as Record<string, unknown>;
  const spec = typeof r.model === "string" ? MODELS[r.model] : undefined;
  if (!spec || r.provider !== spec.provider) return BAD_REQUEST;
  if (typeof r.system !== "string" || typeof r.prompt !== "string") {
    return BAD_REQUEST;
  }
  const temperature = r.temperature;
  if (
    typeof temperature !== "number" || !(temperature >= 0 && temperature <= 2)
  ) return BAD_REQUEST;
  const images = r.images ?? [];
  if (!Array.isArray(images)) return BAD_REQUEST;
  if (images.length > 0 && !spec.vision) return BAD_REQUEST;
  for (const img of images) {
    if (
      typeof img !== "object" || img === null ||
      !IMAGE_MIMES.has((img as GatewayImage).mime) ||
      typeof (img as GatewayImage).base64 !== "string"
    ) return BAD_REQUEST;
  }
  return {
    provider: spec.provider,
    model: r.model as string,
    system: r.system,
    prompt: r.prompt,
    images: images as GatewayImage[],
    temperature,
  };
}

export function buildUpstream(
  req: GatewayRequest,
  keys: Record<string, string>,
): { url: string; init: RequestInit } {
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    "Authorization": `Bearer ${keys[req.provider]}`,
  };
  if (req.provider === "openrouter") headers["X-Title"] = "Tavli";
  const body = {
    model: req.model,
    temperature: req.temperature,
    response_format: { type: "json_object" },
    messages: [
      { role: "system", content: req.system },
      {
        role: "user",
        content: req.images.length === 0 ? req.prompt : [
          { type: "text", text: req.prompt },
          ...req.images.map((i) => ({
            type: "image_url",
            image_url: { url: `data:${i.mime};base64,${i.base64}` },
          })),
        ],
      },
    ],
  };
  return {
    url: `${BASE_URL[req.provider]}chat/completions`,
    init: { method: "POST", headers, body: JSON.stringify(body) },
  };
}

type Mapped = { status: number; body: Record<string, unknown> };
const PROVIDER_ERROR: Mapped = {
  status: 502,
  body: { error: "provider_error" },
};

export async function mapUpstream(res: Response): Promise<Mapped> {
  if (res.status === 429) {
    const text = await res.text().catch(() => "");
    const seconds = Number(res.headers.get("retry-after"));
    const t = text.toLowerCase();
    const daily = ["perday", "per day", "per_day", "daily"].some((s) =>
      t.includes(s)
    );
    return {
      status: 429,
      body: {
        error: "rate_limited",
        ...(Number.isFinite(seconds) && res.headers.has("retry-after")
          ? { retry_after: seconds }
          : {}),
        daily,
      },
    };
  }
  if (res.status === 404) {
    return { status: 404, body: { error: "model_not_found" } };
  }
  if (res.status !== 200) return PROVIDER_ERROR;
  try {
    const data = await res.json();
    const content = data?.choices?.[0]?.message?.content;
    if (typeof content !== "string" || content.trim() === "") {
      return PROVIDER_ERROR;
    }
    return { status: 200, body: { text: content } };
  } catch (_) {
    return PROVIDER_ERROR;
  }
}
