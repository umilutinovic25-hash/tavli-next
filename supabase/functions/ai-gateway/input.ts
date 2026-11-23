import type { Kind } from "./providers.ts";

export const maxBodyBytes = 1_500_000;
const maxPromptLength = 40_000;
const maxImagePixels = 16_000_000;

export const tasks: ReadonlyMap<string, Kind> = new Map([
  ["recipe_from_image", "vision"],
  ["recipe_from_name", "text"],
  ["recipe_refine", "text"],
  ["plan_outline", "text"],
  ["recipe_summaries", "text"],
  ["pantry_from_photo", "vision"],
  // Glasovni nacrt recepta (spec 027): prepis i nacrt, odgovor su radnje.
  ["voice_draft_actions", "text"],
]);

export interface Completion {
  kind: Kind;
  model: string;
  system: string;
  prompt: string;
  image?: string;
  temperature: number;
}

export interface EmbeddingRequest {
  inputs: Array<
    { text: string; taskType: "RETRIEVAL_QUERY" | "RETRIEVAL_DOCUMENT" }
  >;
}

const maxEmbeddingInputs = 32;
const maxEmbeddingInputLength = 8_000;
const maxEmbeddingTotalLength = 40_000;

export function parseEmbeddingRequest(
  value: unknown,
): EmbeddingRequest | undefined {
  const body = record(value);
  if (
    !body || Object.keys(body).length !== 2 ||
    body.task !== "recipe_embeddings" ||
    !Array.isArray(body.inputs) || body.inputs.length < 1 ||
    body.inputs.length > maxEmbeddingInputs
  ) return;
  const inputs: EmbeddingRequest["inputs"] = [];
  let totalLength = 0;
  let queryCount = 0;
  for (const raw of body.inputs) {
    const item = record(raw);
    if (!item || Object.keys(item).length !== 2) return;
    const { text, taskType } = item;
    if (
      typeof text !== "string" || !text.trim() ||
      text.length > maxEmbeddingInputLength ||
      (taskType !== "RETRIEVAL_QUERY" && taskType !== "RETRIEVAL_DOCUMENT")
    ) return;
    totalLength += text.length;
    if (totalLength > maxEmbeddingTotalLength) return;
    if (taskType === "RETRIEVAL_QUERY" && ++queryCount > 1) return;
    inputs.push({ text, taskType });
  }
  return { inputs };
}

export class BodyTooLarge extends Error {}

export async function boundedJson(
  body: ReadableStream<Uint8Array> | null,
  limit: number,
): Promise<unknown> {
  if (!body) throw new SyntaxError();
  const reader = body.getReader();
  const decoder = new TextDecoder("utf-8", { fatal: true });
  const chunks: string[] = [];
  let size = 0;
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > limit) throw new BodyTooLarge();
      chunks.push(decoder.decode(value, { stream: true }));
    }
    chunks.push(decoder.decode());
    return JSON.parse(chunks.join(""));
  } catch (error) {
    await reader.cancel().catch(() => {});
    throw error;
  } finally {
    reader.releaseLock();
  }
}

export function record(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : undefined;
}

function boundedPixels(width: number, height: number): boolean {
  return width > 0 && height > 0 && width * height <= maxImagePixels;
}

function jpegDimensions(bytes: DataView): boolean {
  if (bytes.byteLength < 4 || bytes.getUint16(0) !== 0xffd8) return false;
  const end = bytes.byteLength - 2;
  if (bytes.getUint16(end) !== 0xffd9) return false;
  const frameMarkers = [
    0xc0,
    0xc1,
    0xc2,
    0xc3,
    0xc5,
    0xc6,
    0xc7,
    0xc9,
    0xca,
    0xcb,
    0xcd,
    0xce,
    0xcf,
  ];
  for (let offset = 2; offset + 3 < end;) {
    if (bytes.getUint8(offset++) !== 0xff) return false;
    while (offset < end && bytes.getUint8(offset) === 0xff) offset++;
    if (offset + 2 >= end) return false;
    const marker = bytes.getUint8(offset++);
    if (marker === 0xda || marker === 0xd9) return false;
    const length = bytes.getUint16(offset);
    if (length < 2 || offset + length > end) return false;
    if (frameMarkers.includes(marker)) {
      if (length < 8) return false;
      return boundedPixels(
        bytes.getUint16(offset + 5),
        bytes.getUint16(offset + 3),
      );
    }
    offset += length;
  }
  return false;
}

function validImage(value: string): boolean {
  const match = /^data:image\/(jpeg|png);base64,([A-Za-z0-9+/]+={0,2})$/.exec(
    value,
  );
  if (!match) return false;
  try {
    const raw = Uint8Array.fromBase64(match[2], {
      lastChunkHandling: "strict",
    });
    const bytes = new DataView(raw.buffer, raw.byteOffset, raw.byteLength);
    if (match[1] === "jpeg") return jpegDimensions(bytes);
    return bytes.byteLength >= 33 &&
      bytes.getUint32(0) === 0x89504e47 &&
      bytes.getUint32(4) === 0x0d0a1a0a &&
      bytes.getUint32(8) === 13 &&
      bytes.getUint32(12) === 0x49484452 &&
      boundedPixels(bytes.getUint32(16), bytes.getUint32(20));
  } catch {
    return false;
  }
}

const fields = new Set([
  "task",
  "model",
  "system",
  "prompt",
  "images",
  "temperature",
]);

export function parseCompletion(value: unknown): Completion | undefined {
  const body = record(value);
  if (!body || Object.keys(body).some((key) => !fields.has(key))) return;
  const { task, model, system, prompt, images = [], temperature = 0.1 } = body;
  const kind = typeof task === "string" ? tasks.get(task) : undefined;
  if (
    !kind || typeof model !== "string" || typeof system !== "string" ||
    typeof prompt !== "string" || !system.trim() || !prompt.trim() ||
    system.length + prompt.length > maxPromptLength ||
    typeof temperature !== "number" || !Number.isFinite(temperature) ||
    temperature < 0 || temperature > 1 || !Array.isArray(images)
  ) return;
  if (kind === "text") {
    if (images.length !== 0) return;
    return { kind, model, system, prompt, temperature };
  }
  if (
    images.length !== 1 || typeof images[0] !== "string" ||
    !validImage(images[0])
  ) return;
  return { kind, model, system, prompt, temperature, image: images[0] };
}
