export type RetailerSource = {
  sourceId: "delhaize" | "europrom";
  retailer: string;
  url: string;
  downloadUrl: string;
};

export type ParsedPrice = {
  retailer: string;
  retailerFormat: string;
  barcode: string;
  productName: string;
  measure: string;
  priceListType: "VAZECI_CENOVNIK";
  priceDate: string;
  regularPriceParas: number;
  rowSha256: string;
};

const MAX_CSV_BYTES = 20 * 1024 * 1024;
const MAX_ROWS = 200_000;
const MAX_COLUMNS = 64;

const normalizeHeader = (value: string) =>
  value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .trim()
    .toUpperCase()
    .replace(/[^A-Z0-9]+/g, "_")
    .replace(/^_|_$/g, "");

function parseCsv(text: string): string[][] {
  const rows: string[][] = [];
  let row: string[] = [];
  let field = "";
  let quoted = false;
  for (let i = 0; i < text.length; i++) {
    const char = text[i];
    if (quoted) {
      if (char === '"') {
        if (text[i + 1] === '"') {
          field += '"';
          i++;
        } else {
          quoted = false;
        }
      } else {
        field += char;
      }
      continue;
    }
    if (char === '"' && field.length === 0) {
      quoted = true;
    } else if (char === ";") {
      row.push(field);
      field = "";
      if (row.length >= MAX_COLUMNS) throw new Error("too_many_columns");
    } else if (char === "\n" || char === "\r") {
      if (char === "\r" && text[i + 1] === "\n") i++;
      row.push(field);
      field = "";
      if (row.some((value) => value.trim() !== "")) {
        rows.push(row);
        if (rows.length > MAX_ROWS + 1) throw new Error("too_many_rows");
      }
      row = [];
    } else {
      field += char;
    }
  }
  if (quoted) throw new Error("unterminated_quoted_field");
  row.push(field);
  if (row.some((value) => value.trim() !== "")) rows.push(row);
  if (rows.length > MAX_ROWS + 1) throw new Error("too_many_rows");
  return rows;
}

function parseDate(value: string): string {
  const input = value.trim();
  if (/^\d{4}-\d{2}-\d{2}$/.test(input)) return input;
  const local = input.match(/^(\d{1,2})\.(\d{1,2})\.(\d{4})\.?$/);
  if (!local) throw new Error("invalid_price_date");
  return `${local[3]}-${local[2].padStart(2, "0")}-${
    local[1].padStart(2, "0")
  }`;
}

function parsePriceParas(value: string): number {
  let input = value.trim().replace(/\s/g, "").replace(/рсд|дин/gi, "");
  if (input.includes(",") && input.includes(".")) {
    input = input.lastIndexOf(",") > input.lastIndexOf(".")
      ? input.replace(/\./g, "").replace(",", ".")
      : input.replace(/,/g, "");
  } else if (input.includes(",")) {
    input = input.replace(",", ".");
  }
  if (!/^\d+(?:\.\d{1,2})?$/.test(input)) {
    throw new Error("invalid_regular_price");
  }
  const [whole, fraction = ""] = input.split(".");
  const amount = Number(whole) * 100 + Number(fraction.padEnd(2, "0"));
  if (!Number.isSafeInteger(amount) || amount < 0) {
    throw new Error("invalid_regular_price");
  }
  return amount;
}

async function sha256(bytes: Uint8Array): Promise<string> {
  const stableBuffer = new ArrayBuffer(bytes.byteLength);
  new Uint8Array(stableBuffer).set(bytes);
  const digest = await crypto.subtle.digest("SHA-256", stableBuffer);
  return Array.from(
    new Uint8Array(digest),
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
}

export async function parseCurrentPriceList(
  bytes: Uint8Array,
  source: RetailerSource,
): Promise<{ sourceSha256: string; rows: ParsedPrice[] }> {
  if (bytes.length === 0 || bytes.length > MAX_CSV_BYTES) {
    throw new Error("invalid_csv_size");
  }
  const text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  const parsed = parseCsv(text);
  const rawHeaders = parsed.shift();
  if (!rawHeaders) throw new Error("missing_csv_header");
  const headers = rawHeaders.map((name) =>
    normalizeHeader(name.replace(/^\uFEFF/, ""))
  );
  const index = (name: string) => headers.indexOf(name);
  const formatIndex = [
    "TRGOVAC_FORMAT",
    "NAZIV_TRGOVCA_FORMATA",
    "NAZIV_TRGOVCA_FORMATA",
  ].map(index).find((n) => n >= 0);
  const fields = {
    barcode: index("BARKOD"),
    product: index("NAZIV_PROIZVODA"),
    measure: index("JEDINICA_MERE"),
    listType: index("VRSTA_CENOVNIKA"),
    date: index("DATUM_CENOVNIKA"),
    regular: index("REDOVNA_CENA"),
  };
  if (
    formatIndex === undefined || Object.values(fields).some((n) => n < 0)
  ) throw new Error("unsupported_csv_schema");

  const sourceHash = await sha256(bytes);
  const rows: ParsedPrice[] = [];
  for (const record of parsed) {
    if (record.length !== headers.length) throw new Error("invalid_csv_row");
    if (record[fields.listType].trim().toUpperCase() !== "VAZECI_CENOVNIK") {
      continue;
    }
    const barcode = record[fields.barcode].trim();
    const productName = record[fields.product].trim();
    const retailerFormat = record[formatIndex!].trim();
    const measure = record[fields.measure].trim();
    if (
      !barcode || barcode.length > 64 || !productName ||
      productName.length > 500 || !retailerFormat ||
      retailerFormat.length > 120 || !measure || measure.length > 64
    ) throw new Error("invalid_current_price_row");
    const priceDate = parseDate(record[fields.date]);
    const regularPriceParas = parsePriceParas(record[fields.regular]);
    const rowSha256 = await sha256(
      new TextEncoder().encode(JSON.stringify(record)),
    );
    rows.push({
      retailer: source.retailer,
      retailerFormat,
      barcode,
      productName,
      measure,
      priceListType: "VAZECI_CENOVNIK",
      priceDate,
      regularPriceParas,
      rowSha256,
    });
  }
  if (rows.length === 0) throw new Error("no_current_price_rows");
  return { sourceSha256: sourceHash, rows };
}

export const retailerSources: RetailerSource[] = [
  {
    sourceId: "delhaize",
    retailer: "Delhaize Serbia",
    url:
      "https://data.gov.rs/sr/datasets/r/aa0a4ab4-1dc8-49e2-abef-67612a2abcbb",
    downloadUrl:
      "https://tsmdelhaizeserbia.delhaize.rs/PublicDoc/cene_proizvoda_Delhaize.csv",
  },
  {
    sourceId: "europrom",
    retailer: "Europrom",
    url:
      "https://data.gov.rs/sr/datasets/r/7bcd8e5e-a89f-4dc8-9b7d-70ce27e31096",
    downloadUrl:
      "https://api.nitsolutions.rs/api/v1/external/cenovnik/00fc017c-0f22-40c2-9e38-50f4c4a66f80.csv",
  },
];

export const importLimits = { maxCsvBytes: MAX_CSV_BYTES, maxRows: MAX_ROWS };
