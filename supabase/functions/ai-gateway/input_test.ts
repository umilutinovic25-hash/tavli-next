// Zadatak glasovnog nacrta (spec 027) je tekstualni: bez slike prolazi,
// sa slikom se odbija pre limita.
import { assertEquals } from "jsr:@std/assert@1";

import { parseCompletion, parseEmbeddingRequest } from "./input.ts";

const base = {
  task: "voice_draft_actions",
  model: "groq/openai/gpt-oss-120b",
  system: "Return JSON",
  prompt: 'Transcript: "Sarma za šest osoba."',
  temperature: 0.1,
};

Deno.test("voice_draft_actions is a text task", () => {
  assertEquals(parseCompletion(base)?.kind, "text");
});

Deno.test("voice_draft_actions rejects an image", () => {
  assertEquals(
    parseCompletion({ ...base, images: ["data:image/png;base64,AAAA"] }),
    undefined,
  );
});

Deno.test("recipe embeddings accept one query and bounded document inputs", () => {
  const request = parseEmbeddingRequest({
    task: "recipe_embeddings",
    inputs: [
      { text: "Sarma i kupus", taskType: "RETRIEVAL_DOCUMENT" },
      { text: "Jelo sa kupusom", taskType: "RETRIEVAL_QUERY" },
    ],
  });
  assertEquals(request?.inputs.length, 2);
});

Deno.test("recipe embeddings reject invalid, unbounded and query-free input", () => {
  const query = { text: "kupus", taskType: "RETRIEVAL_QUERY" };
  assertEquals(
    parseEmbeddingRequest({ task: "recipe_embeddings", inputs: [] }),
    undefined,
  );
  assertEquals(
    parseEmbeddingRequest({
      task: "recipe_embeddings",
      inputs: [query, query],
    }),
    undefined,
  );
  assertEquals(
    parseEmbeddingRequest({
      task: "recipe_embeddings",
      inputs: [{ ...query, text: "x".repeat(8_001) }],
    }),
    undefined,
  );
  assertEquals(
    parseEmbeddingRequest({
      task: "recipe_embeddings",
      inputs: [{ text: "private", taskType: "unknown" }],
    }),
    undefined,
  );
  assertEquals(
    parseEmbeddingRequest({
      task: "recipe_embeddings",
      inputs: Array.from({ length: 33 }, (_, index) => ({
        text: `document ${index}`,
        taskType: "RETRIEVAL_DOCUMENT",
      })),
    }),
    undefined,
  );
});
