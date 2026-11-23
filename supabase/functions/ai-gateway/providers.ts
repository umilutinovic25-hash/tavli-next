export type Kind = "text" | "vision";
export type Env = (name: string) => string | undefined;

const providers = {
  gemini: {
    url:
      "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
    secret: "GEMINI_API_KEY",
    tokenField: "max_tokens",
  },
  groq: {
    url: "https://api.groq.com/openai/v1/chat/completions",
    secret: "GROQ_API_KEY",
    tokenField: "max_completion_tokens",
  },
  openrouter: {
    url: "https://openrouter.ai/api/v1/chat/completions",
    secret: "OPENROUTER_API_KEY",
    tokenField: "max_tokens",
  },
  openai: {
    url: "https://api.openai.com/v1/chat/completions",
    secret: "OPENAI_API_KEY",
    tokenField: "max_completion_tokens",
  },
} as const;

type Provider = keyof typeof providers;

interface Model {
  provider: Provider;
  name: string;
  timeoutSeconds: number;
}

function model(provider: Provider, name: string, timeoutSeconds = 30): Model {
  return { provider, name, timeoutSeconds };
}

const openai = model("openai", "default", 60);
const geminiFlash = model("gemini", "gemini-flash-latest");
const geminiPro = model("gemini", "gemini-pro-latest", 60);
const geminiLite = model("gemini", "gemini-flash-lite-latest");
const openrouter = model("openrouter", "google/gemma-3-27b-it:free");

export const chains: Record<Kind, readonly Model[]> = {
  vision: [
    openai,
    geminiFlash,
    model("groq", "qwen/qwen3.6-27b"),
    geminiPro,
    geminiLite,
    openrouter,
  ],
  text: [
    openai,
    geminiPro,
    model("groq", "openai/gpt-oss-120b"),
    geminiFlash,
    model("groq", "llama-3.3-70b-versatile"),
    geminiLite,
    openrouter,
  ],
};

export function modelId(model: Model): string {
  return model.provider + "/" + model.name;
}

export function resolveModel(candidate: Model, env: Env) {
  const config = providers[candidate.provider];
  const key = env(config.secret)?.trim();
  if (!key) return null;
  let name = candidate.name;
  if (candidate.provider === "openai") {
    if (env("AI_OPENAI_ENABLED") !== "1") return null;
    name = env("OPENAI_MODEL")?.trim() ?? "";
    if (!name) return null;
  }
  return { ...config, key, model: { ...candidate, name } };
}

export const embeddingModel = "text-embedding-3-small";

export function resolveEmbedding(env: Env) {
  const key = env("OPENAI_API_KEY")?.trim();
  if (env("AI_OPENAI_EMBEDDINGS_ENABLED") !== "1" || !key) return null;
  return {
    key,
    model: embeddingModel,
    url: "https://api.openai.com/v1/embeddings",
  };
}
