import {
  BodyTooLarge,
  boundedJson,
  type Completion,
  type EmbeddingRequest,
  maxBodyBytes,
  parseCompletion,
  parseEmbeddingRequest,
  record,
} from "./input.ts";
import {
  chains,
  embeddingModel,
  type Env,
  type Kind,
  modelId,
  resolveEmbedding,
  resolveModel,
} from "./providers.ts";

const maxProviderResponseBytes = 800_000;

type QuotaLimit = "daily" | "global" | "minute" | "concurrent";

export type Reservation =
  | { id: string }
  | { limit: QuotaLimit; retryAfterSeconds: number };

export interface Limits {
  daily: number;
  minute: number;
  concurrent: number;
  global: number;
}

interface GatewayDependencies {
  env: Env;
  authenticate(token: string): Promise<string | null>;
  reserve(uid: string, kind: Kind, limits: Limits): Promise<Reservation>;
  release(id: string): Promise<void>;
  send: typeof fetch;
}

function response(status: number, body: Record<string, unknown>, headers = {}) {
  return Response.json(body, {
    status,
    headers: { "Cache-Control": "no-store", ...headers },
  });
}

function failure(status: number, error: string) {
  return response(status, { error });
}

function limit(env: Env, name: string, fallback: number): number {
  const raw = env(name);
  if (raw === undefined) return fallback;
  const value = Number(raw);
  if (!Number.isInteger(value) || value < 1 || value > 2_147_483_647) {
    throw new Error("invalid_gateway_limit");
  }
  return value;
}

function limitsFor(env: Env, kind: Kind): Limits {
  return {
    daily: kind === "vision"
      ? limit(env, "AI_DAILY_VISION_LIMIT", 30)
      : limit(env, "AI_DAILY_TEXT_LIMIT", 150),
    minute: limit(env, "AI_PER_MINUTE_LIMIT", 20),
    concurrent: limit(env, "AI_CONCURRENT_LIMIT", 2),
    global: limit(env, "AI_GLOBAL_DAILY_LIMIT", 2000),
  };
}

function quotaResponse(
  denied: Extract<Reservation, { limit: QuotaLimit }>,
  kind: Kind,
) {
  const { limit, retryAfterSeconds } = denied;
  if (limit === "concurrent") {
    return response(429, { error: "busy", retryAfterSeconds });
  }
  return response(429, {
    error: "quota_exceeded",
    limit,
    ...(limit === "daily" ? { kind } : {}),
    retryAfterSeconds,
  });
}

async function complete(
  input: Completion,
  selected: NonNullable<ReturnType<typeof resolveModel>>,
  send: typeof fetch,
): Promise<Response> {
  const { key, model, tokenField, url } = selected;
  const signal = AbortSignal.timeout(model.timeoutSeconds * 1000);
  try {
    const upstream = await send(url, {
      method: "POST",
      redirect: "error",
      signal,
      headers: {
        Authorization: "Bearer " + key,
        "Content-Type": "application/json",
        ...(model.provider === "openrouter" ? { "X-Title": "Tavli" } : {}),
      },
      body: JSON.stringify({
        model: model.name,
        [tokenField]: 4096,
        response_format: { type: "json_object" },
        ...(model.provider === "openai"
          ? {}
          : { temperature: input.temperature }),
        ...(model.name === "qwen/qwen3.6-27b"
          ? { reasoning_effort: "none" }
          : {}),
        messages: [
          { role: "system", content: input.system },
          {
            role: "user",
            content: input.image
              ? [
                { type: "text", text: input.prompt },
                { type: "image_url", image_url: { url: input.image } },
              ]
              : input.prompt,
          },
        ],
      }),
    });

    if (!upstream.ok) {
      await upstream.body?.cancel().catch(() => {});
      if (upstream.status === 404) return failure(503, "model_unavailable");
      if (upstream.status === 429) {
        const retry = upstream.headers.get("Retry-After");
        const seconds = retry && /^\d+$/.test(retry) ? Number(retry) : NaN;
        return response(429, {
          error: "provider_rate_limited",
          ...(Number.isSafeInteger(seconds)
            ? { retryAfterSeconds: seconds }
            : {}),
        });
      }
      return failure(502, "provider_error");
    }

    const payload = record(
      await boundedJson(upstream.body, maxProviderResponseBytes),
    );
    const first = Array.isArray(payload?.choices)
      ? record(payload.choices[0])
      : undefined;
    const content = record(first?.message)?.content;
    if (typeof content !== "string" || !content.trim()) {
      return failure(502, "provider_error");
    }
    return response(200, { content, model: input.model });
  } catch {
    return signal.aborted
      ? failure(504, "timeout")
      : failure(502, "provider_error");
  }
}

async function embed(
  input: EmbeddingRequest,
  selected: NonNullable<ReturnType<typeof resolveEmbedding>>,
  send: typeof fetch,
): Promise<Response> {
  const signal = AbortSignal.timeout(30_000);
  try {
    const upstream = await send(selected.url, {
      method: "POST",
      redirect: "error",
      signal,
      headers: {
        Authorization: "Bearer " + selected.key,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: selected.model,
        input: input.inputs.map((item) => item.text),
        dimensions: 768,
        encoding_format: "float",
      }),
    });
    if (!upstream.ok) {
      await upstream.body?.cancel().catch(() => {});
      if (upstream.status === 404) return failure(503, "model_unavailable");
      if (upstream.status === 429) {
        const retry = upstream.headers.get("Retry-After");
        const seconds = retry && /^\d+$/.test(retry) ? Number(retry) : NaN;
        return response(429, {
          error: "provider_rate_limited",
          ...(Number.isSafeInteger(seconds)
            ? { retryAfterSeconds: seconds }
            : {}),
        });
      }
      return failure(502, "provider_error");
    }
    const payload = record(
      await boundedJson(upstream.body, maxProviderResponseBytes),
    );
    if (
      payload?.model !== selected.model || !Array.isArray(payload?.data) ||
      payload.data.length !== input.inputs.length
    ) {
      return failure(502, "provider_error");
    }
    const vectors = new Array<number[]>(input.inputs.length);
    const seen = new Set<number>();
    for (const raw of payload.data) {
      const item = record(raw);
      const index = item?.index;
      const values = item?.embedding;
      if (
        typeof index !== "number" || !Number.isSafeInteger(index) ||
        index < 0 || index >= vectors.length || seen.has(index) ||
        !Array.isArray(values) ||
        values.length !== 768 ||
        values.some((value) =>
          typeof value !== "number" || !Number.isFinite(value)
        )
      ) return failure(502, "provider_error");
      vectors[index] = values as number[];
      seen.add(index);
    }
    if (seen.size !== vectors.length) {
      return failure(502, "provider_error");
    }
    return response(200, { model: embeddingModel, embeddings: vectors });
  } catch {
    return signal.aborted
      ? failure(504, "timeout")
      : failure(502, "provider_error");
  }
}

export function gateway(
  { env, authenticate, reserve, release, send }: GatewayDependencies,
) {
  return async (request: Request): Promise<Response> => {
    if (request.method !== "GET" && request.method !== "POST") {
      return response(405, { error: "method_not_allowed" }, {
        Allow: "GET, POST",
      });
    }
    const token = /^Bearer ([^\s]+)$/i.exec(
      request.headers.get("Authorization") ?? "",
    )?.[1];
    if (!token) return failure(401, "unauthorized");

    try {
      const uid = await authenticate(token);
      if (!uid) return failure(401, "unauthorized");
      if (env("AI_GATEWAY_DISABLED") === "1") {
        return failure(503, "gateway_unavailable");
      }
      if (request.method === "GET") {
        return response(200, {
          text: chains.text.filter((candidate) => resolveModel(candidate, env))
            .map(modelId),
          vision: chains.vision.filter((candidate) =>
            resolveModel(candidate, env)
          ).map(modelId),
        });
      }

      if (Number(request.headers.get("Content-Length")) > maxBodyBytes) {
        return failure(413, "too_large");
      }
      let body: unknown;
      try {
        body = await boundedJson(request.body, maxBodyBytes);
      } catch (error) {
        return error instanceof BodyTooLarge
          ? failure(413, "too_large")
          : failure(400, "bad_request");
      }
      if (record(body)?.task === "recipe_embeddings") {
        const embeddingInput = parseEmbeddingRequest(body);
        if (!embeddingInput) return failure(400, "bad_request");
        const selected = resolveEmbedding(env);
        if (!selected) return failure(503, "model_unavailable");
        const reservation = await reserve(uid, "text", limitsFor(env, "text"));
        if ("limit" in reservation) return quotaResponse(reservation, "text");
        try {
          return await embed(embeddingInput, selected, send);
        } finally {
          try {
            await release(reservation.id);
          } catch {
            console.warn("ai_gateway_release_failed");
          }
        }
      }
      const input: Completion | undefined = parseCompletion(body);
      if (!input) return failure(400, "bad_request");

      const candidate = chains[input.kind].find((entry) =>
        modelId(entry) === input.model
      );
      if (!candidate) return failure(400, "bad_request");
      const selected = resolveModel(candidate, env);
      if (!selected) return failure(503, "model_unavailable");

      const reservation = await reserve(
        uid,
        input.kind,
        limitsFor(env, input.kind),
      );
      if ("limit" in reservation) return quotaResponse(reservation, input.kind);
      try {
        return await complete(input, selected, send);
      } finally {
        try {
          await release(reservation.id);
        } catch {
          // The RPC expires abandoned reservations after 90 seconds.
          console.warn("ai_gateway_release_failed");
        }
      }
    } catch {
      return failure(500, "internal");
    }
  };
}
