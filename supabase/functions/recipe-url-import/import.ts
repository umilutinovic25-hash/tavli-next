import ipaddr from "npm:ipaddr.js@2.2.0";
import { parse } from "npm:node-html-parser@6.1.13";
import { lookup } from "node:dns/promises";

const excluded4 = [
  "0.0.0.0/8",
  "10.0.0.0/8",
  "100.64.0.0/10",
  "127.0.0.0/8",
  "169.254.0.0/16",
  "172.16.0.0/12",
  "192.0.0.0/24",
  "192.0.2.0/24",
  "192.88.99.0/24",
  "192.168.0.0/16",
  "198.18.0.0/15",
  "198.51.100.0/24",
  "203.0.113.0/24",
  "224.0.0.0/4",
  "240.0.0.0/4",
].map((x) => ipaddr.parseCIDR(x));
const global6 = ipaddr.parseCIDR("2000::/3");
const excluded6 = ["2001::/23", "2001:db8::/32", "2002::/16", "3fff::/20"].map((
  x,
) => ipaddr.parseCIDR(x));

// Edge runtime (Deno 2.1) nema globalni Node `Buffer`, pa bajtove spajamo ručno.
export function concatBytes(chunks: Uint8Array[]): Uint8Array {
  const out = new Uint8Array(chunks.reduce((n, c) => n + c.length, 0));
  let offset = 0;
  for (const chunk of chunks) {
    out.set(chunk, offset);
    offset += chunk.length;
  }
  return out;
}

export function isPublicAddress(value: string): boolean {
  if (!ipaddr.isValid(value)) return false;
  const address = ipaddr.process(value);
  if (address.kind() === "ipv4") {
    const a = address as ipaddr.IPv4;
    return !excluded4.some(([network, bits]) =>
      a.match(network as ipaddr.IPv4, bits)
    );
  }
  const a = address as ipaddr.IPv6;
  return a.match(global6[0] as ipaddr.IPv6, global6[1]) &&
    !excluded6.some(([network, bits]) => a.match(network as ipaddr.IPv6, bits));
}

export function validateUrl(input: string): URL {
  if (input.length > 2048) throw new Error("url");
  const u = new URL(input);
  if (
    !(["http:", "https:"].includes(u.protocol)) || !u.hostname || u.username ||
    u.password || (u.port && u.port !== "80" && u.port !== "443")
  ) throw new Error("url");
  u.hash = "";
  return u;
}

export async function resolvePublic(
  url: URL,
  resolver: (host: string) => Promise<string[]> = async (host) =>
    (await lookup(host, { all: true })).map((a) => a.address),
): Promise<string> {
  const host = url.hostname.replace(/^\[|\]$/g, "");
  const ips = ipaddr.isValid(host) ? [host] : await resolver(host);
  if (!ips.length || ips.some((ip) => !isPublicAddress(ip))) {
    throw new Error("address");
  }
  return ips[0];
}

// The lookup callback returns the already-checked IP to the HTTP stack; TLS
// still verifies the original hostname. Redirects get a fresh validation.
type PageResponse = { status: number; location?: string; body: string };
type FetchOptions = {
  resolver?: (host: string) => Promise<string[]>;
  request?: (url: URL, ip: string, remaining: number) => Promise<PageResponse>;
};
export async function fetchPage(
  input: string,
  options: FetchOptions = {},
): Promise<string> {
  let url = validateUrl(input);
  const deadline = Date.now() + 12000;
  for (let redirects = 0; redirects <= 3; redirects++) {
    const remainingForDns = deadline - Date.now();
    if (remainingForDns <= 0) throw new Error("timeout");
    let dnsTimer: ReturnType<typeof setTimeout> | undefined;
    const ip = await Promise.race([
      resolvePublic(url, options.resolver),
      new Promise<never>((_, reject) => {
        dnsTimer = setTimeout(
          () => reject(new Error("timeout")),
          remainingForDns,
        );
      }),
    ]).finally(() => clearTimeout(dnsTimer));
    const remaining = deadline - Date.now();
    if (remaining <= 0) throw new Error("timeout");
    const response = await (options.request ?? requestPage)(url, ip, remaining);
    if (response.status >= 300 && response.status < 400) {
      if (!response.location || redirects === 3) throw new Error("redirect");
      url = validateUrl(new URL(response.location, url).toString());
      continue;
    }
    return response.body;
  }
  throw new Error("redirect");
}

const MAX_HEAD = 32 * 1024;
const MAX_BODY = 1_000_000;

// Zaglavlje odgovora: status, mala slova imena i ostatak bajtova posle praznog reda.
export function parseHead(
  bytes: Uint8Array,
): { status: number; headers: Map<string, string>; rest: Uint8Array } | null {
  for (let i = 0; i + 3 < bytes.length; i++) {
    if (
      bytes[i] === 13 && bytes[i + 1] === 10 && bytes[i + 2] === 13 &&
      bytes[i + 3] === 10
    ) {
      const lines = new TextDecoder().decode(bytes.subarray(0, i)).split(
        "\r\n",
      );
      const match = /^HTTP\/1\.[01] (\d{3})(?: |$)/.exec(lines[0]);
      if (!match) throw new Error("response");
      const headers = new Map<string, string>();
      for (const line of lines.slice(1)) {
        const colon = line.indexOf(":");
        if (colon <= 0) throw new Error("response");
        const name = line.slice(0, colon).trim().toLowerCase();
        const value = line.slice(colon + 1).trim();
        headers.set(
          name,
          headers.has(name) ? `${headers.get(name)}, ${value}` : value,
        );
      }
      return { status: Number(match[1]), headers, rest: bytes.subarray(i + 4) };
    }
  }
  if (bytes.length > MAX_HEAD) throw new Error("response");
  return null;
}

// Dekodira "chunked" telo; vraća null dok ne stigne završni deo veličine 0.
export function decodeChunked(bytes: Uint8Array): Uint8Array | null {
  const parts: Uint8Array[] = [];
  let pos = 0;
  let total = 0;
  while (true) {
    let lineEnd = -1;
    for (let i = pos; i + 1 < bytes.length; i++) {
      if (bytes[i] === 13 && bytes[i + 1] === 10) {
        lineEnd = i;
        break;
      }
    }
    if (lineEnd < 0) {
      if (bytes.length - pos > 1024) throw new Error("response");
      return null;
    }
    const sizeText = new TextDecoder().decode(bytes.subarray(pos, lineEnd))
      .split(";")[0].trim();
    if (!/^[0-9a-fA-F]{1,8}$/.test(sizeText)) throw new Error("response");
    const size = parseInt(sizeText, 16);
    if (size === 0) return concatBytes(parts);
    const dataStart = lineEnd + 2;
    if (bytes.length < dataStart + size + 2) return null;
    total += size;
    if (total > MAX_BODY) throw new Error("size");
    parts.push(bytes.subarray(dataStart, dataStart + size));
    pos = dataStart + size + 2;
  }
}

// TCP veza ide na već proverenu IP adresu, a TLS proverava sertifikat za
// originalno ime sajta (SNI). Edge runtime ne podržava `lookup` u node:http.
export async function requestPage(
  url: URL,
  ip: string,
  remaining: number,
): Promise<PageResponse> {
  const port = Number(url.port || (url.protocol === "https:" ? 443 : 80));
  let conn: Deno.Conn | undefined;
  let timer: ReturnType<typeof setTimeout> | undefined;
  const deadline = new Promise<never>((_, reject) => {
    timer = setTimeout(() => {
      try {
        conn?.close();
      } catch {
        // veza je već zatvorena
      }
      reject(new Error("timeout"));
    }, remaining);
  });
  try {
    return await Promise.race([
      deadline,
      (async () => {
        const tcp = await Deno.connect({ hostname: ip, port });
        conn = tcp;
        if (url.protocol === "https:") {
          conn = await Deno.startTls(tcp, {
            hostname: url.hostname.replace(/^\[|\]$/g, ""),
          });
        }
        await writeAll(
          conn,
          new TextEncoder().encode(
            `GET ${url.pathname}${url.search} HTTP/1.1\r\n` +
              `Host: ${url.host}\r\n` +
              "Accept: text/html\r\nAccept-Encoding: identity\r\n" +
              "User-Agent: Tavli/1.0\r\nConnection: close\r\n\r\n",
          ),
        );
        return await readResponse(conn);
      })(),
    ]);
  } finally {
    clearTimeout(timer);
    try {
      conn?.close();
    } catch {
      // veza je već zatvorena
    }
  }
}

async function writeAll(conn: Deno.Conn, bytes: Uint8Array) {
  let written = 0;
  while (written < bytes.length) {
    written += await conn.write(bytes.subarray(written));
  }
}

async function readResponse(conn: Deno.Conn): Promise<PageResponse> {
  const chunks: Uint8Array[] = [];
  let received = 0;
  let head: ReturnType<typeof parseHead> = null;
  let bodyStart = 0;
  const buffer = new Uint8Array(16 * 1024);
  while (true) {
    const n = await conn.read(buffer);
    const done = n === null;
    if (!done) {
      received += n;
      if (received > MAX_HEAD + MAX_BODY + 64 * 1024) throw new Error("size");
      chunks.push(buffer.slice(0, n));
    }
    const all = concatBytes(chunks);
    if (!head) {
      head = parseHead(all);
      if (head) bodyStart = all.length - head.rest.length;
    }
    if (!head) {
      if (done) throw new Error("response");
      continue;
    }
    const { status, headers } = head;
    if (status >= 300 && status < 400) {
      return { status, location: headers.get("location"), body: "" };
    }
    if (
      status !== 200 ||
      !(headers.get("content-type") ?? "").toLowerCase().includes("text/html")
    ) throw new Error("response");
    const bodyBytes = all.subarray(bodyStart);
    const encoding = (headers.get("transfer-encoding") ?? "").toLowerCase();
    if (encoding) {
      if (encoding !== "chunked") throw new Error("response");
      const decoded = decodeChunked(bodyBytes);
      if (decoded) return { status, body: new TextDecoder().decode(decoded) };
      if (done) throw new Error("response");
      continue;
    }
    const lengthHeader = headers.get("content-length");
    if (lengthHeader !== undefined) {
      if (!/^\d+$/.test(lengthHeader)) throw new Error("response");
      const length = Number(lengthHeader);
      if (length > MAX_BODY) throw new Error("size");
      if (bodyBytes.length >= length) {
        return {
          status,
          body: new TextDecoder().decode(bodyBytes.subarray(0, length)),
        };
      }
      if (done) throw new Error("response");
      continue;
    }
    if (bodyBytes.length > MAX_BODY) throw new Error("size");
    if (done) return { status, body: new TextDecoder().decode(bodyBytes) };
  }
}

// Sajtovi često u JSON-LD stavljaju HTML entitete (&amp;, &#8217;); rezultat je čist tekst.
const named: Record<string, string> = {
  amp: "&",
  lt: "<",
  gt: ">",
  quot: '"',
  apos: "'",
  nbsp: " ",
};
export function cleanText(value: string): string {
  return value.replace(
    /&(#x[0-9a-fA-F]{1,6}|#\d{1,7}|[a-zA-Z]+);/g,
    (entity, code: string) => {
      if (code[0] !== "#") return named[code.toLowerCase()] ?? entity;
      const point = code[1] === "x" || code[1] === "X"
        ? parseInt(code.slice(2), 16)
        : parseInt(code.slice(1), 10);
      return point > 0 && point <= 0x10ffff
        ? String.fromCodePoint(point)
        : entity;
    },
  ).replace(/\s+/g, " ").trim();
}

type JsonObject = Record<string, unknown>;
function objects(value: unknown): JsonObject[] {
  if (Array.isArray(value)) return value.flatMap(objects);
  if (!value || typeof value !== "object") return [];
  const obj = value as JsonObject;
  return [obj, ...objects(obj["@graph"])];
}
function steps(value: unknown): string[] {
  if (typeof value === "string") {
    return cleanText(value) ? [cleanText(value)] : [];
  }
  if (Array.isArray(value)) return value.flatMap(steps);
  if (!value || typeof value !== "object") return [];
  const obj = value as JsonObject;
  if (typeof obj.text === "string") return steps(obj.text);
  return steps(obj.itemListElement);
}
export function extractRecipe(
  html: string,
): {
  title: string;
  servings: number | null;
  ingredients: string[];
  steps: string[];
} | null {
  const scripts = parse(html).querySelectorAll("script[type]").filter((s) =>
    s.getAttribute("type")?.split(";")[0].trim().toLowerCase() ===
      "application/ld+json"
  );
  for (const script of scripts) {
    let data: unknown;
    try {
      data = JSON.parse(script.rawText);
    } catch {
      continue;
    }
    for (const obj of objects(data)) {
      const types = Array.isArray(obj["@type"]) ? obj["@type"] : [obj["@type"]];
      if (
        !types.some((t) =>
          typeof t === "string" &&
          (t === "Recipe" || t === "https://schema.org/Recipe" ||
            t === "http://schema.org/Recipe")
        )
      ) continue;
      const title = typeof obj.name === "string" ? cleanText(obj.name) : "";
      const ingredients = Array.isArray(obj.recipeIngredient)
        ? obj.recipeIngredient.filter((x): x is string => typeof x === "string")
          .map(cleanText).filter(Boolean)
        : [];
      if (!title || !ingredients.length) continue;
      const yieldValue = Array.isArray(obj.recipeYield)
        ? obj.recipeYield[0]
        : obj.recipeYield;
      const match = /^(\d+)(?:\s+(?:servings?|porcij\w*))?$/i.exec(
        String(yieldValue ?? "").trim(),
      );
      const servings = match ? Number(match[1]) : null;
      return {
        title,
        ingredients,
        steps: steps(obj.recipeInstructions),
        servings: servings && servings > 0 && servings <= 99 ? servings : null,
      };
    }
  }
  return null;
}
