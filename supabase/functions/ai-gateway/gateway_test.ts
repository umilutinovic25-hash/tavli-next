import { gateway, type Reservation } from "./gateway.ts";
import { maxBodyBytes } from "./input.ts";

const textModel = "gemini/gemini-pro-latest";
const imageModel = "groq/qwen/qwen3.6-27b";
const typedRequest = {
  task: "recipe_from_name",
  model: textModel,
  system: "Return a JSON recipe.",
  prompt: "Beans.",
};
const png =
  "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jAfQAAAAASUVORK5CYII=";

function equal(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      "Actual: " + JSON.stringify(actual) + "; expected: " +
        JSON.stringify(expected),
    );
  }
}

function setup({
  env = {},
  reservation = { id: "fake-reservation" },
  upstream = () => Response.json({ choices: [{ message: { content: "{}" } }] }),
}: {
  env?: Record<string, string>;
  reservation?: Reservation;
  upstream?: () => Response;
} = {}) {
  const reserved: unknown[] = [];
  const released: string[] = [];
  const calls: { url: string; init: RequestInit | undefined }[] = [];
  const variables = {
    GEMINI_API_KEY: "fake-gemini",
    GROQ_API_KEY: "fake-groq",
    ...env,
  };
  const handle = gateway({
    env: (name) => (variables as Record<string, string>)[name],
    authenticate: (token) =>
      Promise.resolve(token === "test-session" ? "synthetic-user" : null),
    reserve: (uid, kind, limits) => {
      reserved.push({ uid, kind, limits });
      return Promise.resolve(reservation);
    },
    release: (id) => {
      released.push(id);
      return Promise.resolve();
    },
    send: (url: string | URL | Request, init?: RequestInit) => {
      calls.push({ url: String(url), init });
      return Promise.resolve(upstream());
    },
  });
  return { handle, reserved, released, calls };
}

function post(body: unknown = typedRequest, token = "test-session") {
  return new Request("http://local.test/ai-gateway", {
    method: "POST",
    headers: { Authorization: "Bearer " + token },
    body: JSON.stringify(body),
  });
}

Deno.test("uses only the verified user and reserves and releases one provider attempt", async () => {
  const { handle, reserved, released, calls } = setup();
  const result = await handle(post());
  equal(result.status, 200);
  equal(await result.json(), { content: "{}", model: textModel });
  equal(reserved, [{
    uid: "synthetic-user",
    kind: "text",
    limits: { daily: 150, minute: 20, concurrent: 2, global: 2000 },
  }]);
  equal(released, ["fake-reservation"]);
  equal(calls.length, 1);
  equal(
    calls[0].url,
    "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
  );
  equal(calls[0].init?.redirect, "error");
  equal(JSON.parse(String(calls[0].init?.body)).max_tokens, 4096);
});

Deno.test("rejects unauthorized, forged, invalid and oversized input before quota or provider work", async () => {
  const { handle, reserved, calls } = setup();
  equal((await handle(post(typedRequest, "invalid"))).status, 401);
  equal(
    (await handle(new Request("http://local.test/ai-gateway"))).status,
    401,
  );
  for (
    const extra of [
      { user_id: "forged" },
      { url: "http://local.test/other" },
      { model: "gemini/arbitrary" },
      { model: "constructor" },
      { images: [png] },
      {
        task: "recipe_from_image",
        model: imageModel,
        images: ["data:image/png;base64,YQ=="],
      },
    ]
  ) {
    equal((await handle(post({ ...typedRequest, ...extra }))).status, 400);
  }
  const tooLarge = await handle(
    post({ ...typedRequest, prompt: "a".repeat(maxBodyBytes) }),
  );
  equal(tooLarge.status, 413);
  equal(reserved.length, 0);
  equal(calls.length, 0);
});

Deno.test("daily and concurrency denials have typed errors and skip the provider", async () => {
  for (
    const [limit, body] of [
      ["daily", { error: "quota_exceeded", limit: "daily", kind: "text" }],
      ["concurrent", { error: "busy" }],
    ] as const
  ) {
    const { handle, calls, released } = setup({
      reservation: { limit, retryAfterSeconds: 45 },
    });
    const result = await handle(post());
    equal(result.status, 429);
    equal(await result.json(), { ...body, retryAfterSeconds: 45 });
    equal(calls.length, 0);
    equal(released.length, 0);
  }
});

Deno.test("a provider error returns only a typed error and releases the reservation", async () => {
  const { handle, calls, released } = setup({
    upstream: () =>
      new Response("private upstream error", {
        status: 429,
        headers: { "Retry-After": "15" },
      }),
  });
  const result = await handle(post());
  equal(result.status, 429);
  equal(await result.json(), {
    error: "provider_rate_limited",
    retryAfterSeconds: 15,
  });
  equal(calls.length, 1);
  equal(released, ["fake-reservation"]);
});

Deno.test("accepts image input and sends it to the allowlisted Groq vision model", async () => {
  const { handle, calls, reserved } = setup();
  const result = await handle(post({
    ...typedRequest,
    task: "recipe_from_image",
    model: imageModel,
    images: [png],
  }));
  equal(result.status, 200);
  equal(calls[0].url, "https://api.groq.com/openai/v1/chat/completions");
  const request = JSON.parse(String(calls[0].init?.body));
  equal(request.model, "qwen/qwen3.6-27b");
  equal(request.max_completion_tokens, 4096);
  equal(request.messages[1].content[1].image_url.url, png);
  equal((reserved[0] as { kind: string }).kind, "vision");
});

Deno.test("lists only configured models and places opted-in OpenAI first for both kinds", async () => {
  const authGet = new Request("http://local.test/ai-gateway", {
    headers: { Authorization: "Bearer test-session" },
  });
  const credentials = {
    OPENAI_API_KEY: "fake-openai",
    OPENAI_MODEL: "fake-model",
  };
  const off = setup({ env: credentials });
  const before = await (await off.handle(authGet)).json();
  equal(before.text[0], textModel);
  equal(before.vision[0], "gemini/gemini-flash-latest");
  equal(
    (await off.handle(post({ ...typedRequest, model: "openai/default" })))
      .status,
    503,
  );
  equal(off.reserved.length, 0);

  const on = setup({ env: { ...credentials, AI_OPENAI_ENABLED: "1" } });
  const after = await (await on.handle(authGet)).json();
  equal(after.text, ["openai/default", ...before.text]);
  equal(after.vision, ["openai/default", ...before.vision]);
  equal(on.reserved.length, 0);
  equal(on.calls.length, 0);
  equal(
    (await on.handle(post({ ...typedRequest, model: "openai/default" })))
      .status,
    200,
  );
  equal(JSON.parse(String(on.calls[0].init?.body)).model, "fake-model");
});

Deno.test("the gateway kill switch skips both quota and provider", async () => {
  const { handle, reserved, calls } = setup({
    env: { AI_GATEWAY_DISABLED: "1" },
  });
  const result = await handle(post());
  equal(result.status, 503);
  equal(await result.json(), { error: "gateway_unavailable" });
  equal(reserved.length, 0);
  equal(calls.length, 0);
});

Deno.test("recipe embeddings stay behind auth, OpenAI opt-in and text quota", async () => {
  const values = Array.from({ length: 768 }, (_, index) => index / 768);
  const { handle, reserved, released, calls } = setup({
    env: {
      AI_OPENAI_EMBEDDINGS_ENABLED: "1",
      OPENAI_API_KEY: "fake-openai-key",
    },
    upstream: () =>
      Response.json({
        model: "text-embedding-3-small",
        data: [
          { index: 0, embedding: values },
          { index: 1, embedding: values },
        ],
      }),
  });
  const result = await handle(post({
    task: "recipe_embeddings",
    inputs: [
      { text: "recipe title and ingredients", taskType: "RETRIEVAL_DOCUMENT" },
      { text: "something with vegetables", taskType: "RETRIEVAL_QUERY" },
    ],
  }));
  equal(result.status, 200);
  const body = await result.json() as { model: string; embeddings: number[][] };
  equal(body.model, "text-embedding-3-small");
  equal(body.embeddings.length, 2);
  equal(body.embeddings[0].length, 768);
  equal(reserved.length, 1);
  equal((reserved[0] as { kind: string }).kind, "text");
  equal(released, ["fake-reservation"]);
  equal(calls[0].url, "https://api.openai.com/v1/embeddings");
  equal(calls[0].init?.headers, {
    Authorization: "Bearer fake-openai-key",
    "Content-Type": "application/json",
  });
  const sent = JSON.parse(String(calls[0].init?.body));
  equal(sent.model, "text-embedding-3-small");
  equal(sent.dimensions, 768);
  equal(sent.input, [
    "recipe title and ingredients",
    "something with vegetables",
  ]);
});

Deno.test("embeddings are unavailable before OpenAI is enabled", async () => {
  const { handle, reserved, calls } = setup({
    env: {
      AI_OPENAI_ENABLED: "1",
      OPENAI_API_KEY: "fake-openai-key",
      OPENAI_MODEL: "fake-chat-model",
    },
  });
  const result = await handle(post({
    task: "recipe_embeddings",
    inputs: [{ text: "query", taskType: "RETRIEVAL_QUERY" }],
  }));
  equal(result.status, 503);
  equal(reserved.length, 0);
  equal(calls.length, 0);
});

Deno.test("invalid embedding requests are rejected before quota reservation", async () => {
  const { handle, reserved, calls } = setup({
    env: {
      AI_OPENAI_EMBEDDINGS_ENABLED: "1",
      OPENAI_API_KEY: "fake-openai-key",
    },
  });
  const result = await handle(post({
    task: "recipe_embeddings",
    inputs: [{ text: "query", taskType: "RETRIEVAL_QUERY", owner: "forged" }],
  }));
  equal(result.status, 400);
  equal(reserved.length, 0);
  equal(calls.length, 0);
});

Deno.test("embedding quota rejection makes no OpenAI call", async () => {
  const { handle, reserved, released, calls } = setup({
    env: {
      AI_OPENAI_EMBEDDINGS_ENABLED: "1",
      OPENAI_API_KEY: "fake-openai-key",
    },
    reservation: { limit: "daily", retryAfterSeconds: 60 },
  });
  const result = await handle(post({
    task: "recipe_embeddings",
    inputs: [{ text: "query", taskType: "RETRIEVAL_QUERY" }],
  }));
  equal(result.status, 429);
  equal(await result.json(), {
    error: "quota_exceeded",
    limit: "daily",
    kind: "text",
    retryAfterSeconds: 60,
  });
  equal(reserved.length, 1);
  equal(released.length, 0);
  equal(calls.length, 0);
});
