import {
  importLimits,
  parseCurrentPriceList,
  retailerSources,
} from "./prices.ts";

const env = (name: string) => Deno.env.get(name);
const supabaseUrl = env("SUPABASE_URL");
const serviceRoleKey = env("SUPABASE_SERVICE_ROLE_KEY");
const importSecret = env("STORE_PRICE_IMPORT_SECRET");
if (!supabaseUrl || !serviceRoleKey || !importSecret) {
  throw new Error("missing_store_price_import_configuration");
}

const json = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8" },
  });

function secretMatches(candidate: string | null, expected: string): boolean {
  if (!candidate || candidate.length !== expected.length) return false;
  let difference = 0;
  for (let i = 0; i < expected.length; i++) {
    difference |= candidate.charCodeAt(i) ^ expected.charCodeAt(i);
  }
  return difference === 0;
}

async function rest(
  path: string,
  method = "GET",
  body?: unknown,
  prefer?: string,
): Promise<Response> {
  return fetch(`${supabaseUrl}/rest/v1/${path}`, {
    method,
    headers: {
      apikey: serviceRoleKey!,
      Authorization: `Bearer ${serviceRoleKey!}`,
      "Content-Type": "application/json",
      ...(prefer ? { Prefer: prefer } : {}),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
    redirect: "error",
    signal: AbortSignal.timeout(15_000),
  });
}

async function requireOk(response: Response, code: string): Promise<void> {
  if (response.ok) return;
  await response.body?.cancel().catch(() => {});
  throw new Error(code);
}

async function readBounded(
  response: Response,
  maxBytes: number,
): Promise<Uint8Array> {
  if (!response.body) throw new Error("source_body_missing");
  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > maxBytes) {
        await reader.cancel();
        throw new Error("source_too_large");
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return bytes;
}

async function importSource(source: (typeof retailerSources)[number]) {
  const downloaded = await fetch(source.downloadUrl, {
    headers: { Accept: "text/csv" },
    redirect: "error",
    signal: AbortSignal.timeout(20_000),
  });
  if (!downloaded.ok) {
    await downloaded.body?.cancel().catch(() => {});
    throw new Error("source_download_failed");
  }
  const declaredSize = Number(downloaded.headers.get("content-length") ?? 0);
  if (declaredSize > importLimits.maxCsvBytes) {
    await downloaded.body?.cancel().catch(() => {});
    throw new Error("source_too_large");
  }
  const bytes = await readBounded(downloaded, importLimits.maxCsvBytes);
  const parsed = await parseCurrentPriceList(bytes, source);
  const query = new URLSearchParams({
    select: "id,status",
    source_id: `eq.${source.sourceId}`,
    source_sha256: `eq.${parsed.sourceSha256}`,
  });
  const foundResponse = await rest(`store_price_imports?${query}`);
  await requireOk(foundResponse, "import_lookup_failed");
  const existing = await foundResponse.json() as Array<{
    id: string;
    status: string;
  }>;
  if (existing.some((row) => row.status === "complete")) {
    const refreshed = await rest(
      `store_price_imports?id=eq.${
        existing.find((row) => row.status === "complete")!.id
      }`,
      "PATCH",
      { retrieved_at: new Date().toISOString() },
    );
    await requireOk(refreshed, "import_refresh_failed");
    return { sourceId: source.sourceId, importedRows: 0, skipped: true };
  }

  let importId: string;
  if (existing.length > 0) {
    importId = existing[0].id;
    const reset = await rest(
      `store_price_imports?id=eq.${importId}`,
      "PATCH",
      {
        status: "processing",
        row_count: 0,
        retrieved_at: new Date().toISOString(),
      },
    );
    await requireOk(reset, "import_reset_failed");
    const removed = await rest(
      `store_price_observations?import_id=eq.${importId}`,
      "DELETE",
    );
    await requireOk(removed, "import_cleanup_failed");
  } else {
    const created = await rest(
      "store_price_imports?select=id",
      "POST",
      {
        source_id: source.sourceId,
        source_url: source.url,
        source_sha256: parsed.sourceSha256,
        status: "processing",
      },
      "return=representation",
    );
    await requireOk(created, "import_create_failed");
    const rows = await created.json() as Array<{ id: string }>;
    if (rows.length !== 1 || typeof rows[0]?.id !== "string") {
      throw new Error("import_create_invalid_response");
    }
    importId = rows[0].id;
  }

  try {
    const batchSize = 250;
    for (let start = 0; start < parsed.rows.length; start += batchSize) {
      const observations = parsed.rows.slice(start, start + batchSize).map(
        (row) => ({
          import_id: importId,
          source_id: source.sourceId,
          source_url: source.url,
          source_sha256: parsed.sourceSha256,
          retailer: row.retailer,
          retailer_format: row.retailerFormat,
          barcode: row.barcode,
          product_name: row.productName,
          measure: row.measure,
          price_list_type: row.priceListType,
          price_date: row.priceDate,
          regular_price_paras: row.regularPriceParas,
          row_sha256: row.rowSha256,
        }),
      );
      const inserted = await rest(
        "store_price_observations?on_conflict=import_id,retailer_format,barcode,price_date,row_sha256",
        "POST",
        observations,
        "resolution=merge-duplicates,return=minimal",
      );
      await requireOk(inserted, "import_batch_failed");
    }
    const completed = await rest(
      `store_price_imports?id=eq.${importId}`,
      "PATCH",
      { status: "complete", row_count: parsed.rows.length },
    );
    await requireOk(completed, "import_complete_failed");
  } catch (error) {
    await rest(`store_price_imports?id=eq.${importId}`, "PATCH", {
      status: "failed",
    }).catch(() => {});
    throw error;
  }
  return {
    sourceId: source.sourceId,
    importedRows: parsed.rows.length,
    skipped: false,
  };
}

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return json(405, { error: "method_not_allowed" });
  }
  if (
    !secretMatches(
      request.headers.get("x-store-price-import-secret"),
      importSecret!,
    )
  ) {
    return json(401, { error: "unauthorized" });
  }
  try {
    const results = [];
    for (const source of retailerSources) {
      results.push(await importSource(source));
    }
    return json(200, { results });
  } catch {
    return json(502, { error: "store_price_import_failed" });
  }
});
