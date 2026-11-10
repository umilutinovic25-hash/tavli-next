import {
  assertEquals,
  assertRejects,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  cleanText,
  concatBytes,
  decodeChunked,
  extractRecipe,
  fetchPage,
  isPublicAddress,
  parseHead,
  requestPage,
  resolvePublic,
  validateUrl,
} from "./import.ts";

Deno.test("blocks private and special IP addresses, including mapped IPv6", () => {
  for (
    const ip of [
      "127.0.0.1",
      "10.1.2.3",
      "169.254.169.254",
      "100.64.0.1",
      "192.0.2.1",
      "224.0.0.1",
      "::1",
      "fc00::1",
      "fe80::1",
      "::ffff:127.0.0.1",
      "2001:db8::1",
    ]
  ) {
    assertEquals(isPublicAddress(ip), false, ip);
  }
  assertEquals(isPublicAddress("8.8.8.8"), true);
  assertEquals(isPublicAddress("2606:4700:4700::1111"), true);
});

Deno.test("validates every URL and rejects mixed DNS answers", async () => {
  for (
    const url of [
      "file:///etc/passwd",
      "http://localhost",
      "http://user:pass@example.com",
      "https://example.com:8443",
      "http://127.0.0.1",
    ]
  ) {
    await assertRejects(async () => {
      await resolvePublic(validateUrl(url), async () => ["127.0.0.1"]);
    });
  }
  await assertRejects(() =>
    resolvePublic(
      validateUrl("https://example.com"),
      async () => ["8.8.8.8", "10.0.0.1"],
    )
  );
});

Deno.test("finds Recipe within graph, preserves original ingredient text", () => {
  const html =
    `<script type="application/ld+json">{"@graph":[{"@type":"WebPage"},{"@type":["Thing","Recipe"],"name":"Pita","recipeYield":"4 servings","recipeIngredient":["200 g brašna","so po ukusu"],"recipeInstructions":[{"@type":"HowToSection","itemListElement":[{"@type":"HowToStep","text":"Umesi."}, {"@type":"HowToStep","text":"Ispeci."}]}]}]}</script>`;
  assertEquals(extractRecipe(html), {
    title: "Pita",
    servings: 4,
    ingredients: ["200 g brašna", "so po ukusu"],
    steps: ["Umesi.", "Ispeci."],
  });
});

Deno.test("checks redirects and pins the validated address", async () => {
  const requested: string[] = [];
  const resolver = (host: string): Promise<string[]> =>
    Promise.resolve(host === "public.example" ? ["8.8.8.8"] : ["127.0.0.1"]);
  await assertRejects(() =>
    fetchPage("https://public.example/", {
      resolver,
      request: (_url, ip) => {
        requested.push(ip);
        return Promise.resolve({
          status: 302,
          location: "http://internal.example/",
          body: "",
        });
      },
    })
  );
  assertEquals(requested, ["8.8.8.8"]);
  await assertRejects(() =>
    fetchPage("https://public.example/", {
      resolver,
      request: () =>
        Promise.resolve({ status: 302, location: "/again", body: "" }),
    })
  );
});

Deno.test({
  name: "HTTP transport uses pinned IP and retains original Host",
  permissions: { net: ["127.0.0.1"] },
  fn: async () => {
    const listener = Deno.listen({ hostname: "127.0.0.1", port: 0 });
    const address = listener.addr as Deno.NetAddr;
    const served = (async () => {
      const conn = await listener.accept();
      const buffer = new Uint8Array(4096);
      const n = await conn.read(buffer);
      const request = new TextDecoder().decode(buffer.subarray(0, n ?? 0));
      const response = new TextEncoder().encode(
        "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok",
      );
      await conn.write(response);
      conn.close();
      return request;
    })();
    try {
      const result = await requestPage(
        new URL(`http://unresolvable.invalid:${address.port}/test`),
        "127.0.0.1",
        3000,
      );
      assertEquals(result.body, "ok");
      assertEquals(
        (await served).toLowerCase().includes(
          `host: unresolvable.invalid:${address.port}`,
        ),
        true,
      );
    } finally {
      listener.close();
      await served.catch(() => "");
    }
  },
});

Deno.test("concatBytes spaja delove bez Node Buffer-a", () => {
  const bytes = concatBytes([
    new TextEncoder().encode("Pala"),
    new Uint8Array(),
    new TextEncoder().encode("činke"),
  ]);
  assertEquals(new TextDecoder().decode(bytes), "Palačinke");
});

Deno.test({
  name: "kod funkcije ne koristi globalni Buffer (nema ga u Edge runtime-u)",
  permissions: { read: true },
  fn: async () => {
    for (const file of ["import.ts", "index.ts"]) {
      const source = await Deno.readTextFile(new URL(file, import.meta.url));
      const code = source.replace(/\/\/.*$/gm, "");
      assertEquals(/\bBuffer\b/.test(code), false, file);
    }
  },
});

const bytes = (text: string) => new TextEncoder().encode(text);

// Pokreće lokalni server koji vrati zadati sirovi odgovor i vraća primljeni zahtev.
async function withRawServer(
  response: string,
  run: (port: number) => Promise<unknown>,
): Promise<string> {
  const listener = Deno.listen({ hostname: "127.0.0.1", port: 0 });
  const served = (async () => {
    const conn = await listener.accept();
    const buffer = new Uint8Array(4096);
    const n = await conn.read(buffer);
    await conn.write(bytes(response));
    conn.close();
    return new TextDecoder().decode(buffer.subarray(0, n ?? 0));
  })();
  try {
    await run((listener.addr as Deno.NetAddr).port);
  } finally {
    listener.close();
  }
  return await served.catch(() => "");
}

Deno.test("parseHead čita status i zaglavlja, čeka kraj zaglavlja", () => {
  assertEquals(
    parseHead(bytes("HTTP/1.1 200 OK\r\nContent-Type: text/html")),
    null,
  );
  const head = parseHead(
    bytes("HTTP/1.1 302 Found\r\nLocation: /x\r\nX-A: 1\r\nx-a: 2\r\n\r\ntelo"),
  )!;
  assertEquals(head.status, 302);
  assertEquals(head.headers.get("location"), "/x");
  assertEquals(head.headers.get("x-a"), "1, 2");
  assertEquals(new TextDecoder().decode(head.rest), "telo");
  assertThrows(() => parseHead(bytes("SMTP ready\r\n\r\n")));
  assertThrows(() => parseHead(new Uint8Array(40 * 1024)));
});

Deno.test("decodeChunked spaja delove i odbija neispravne veličine", () => {
  assertEquals(decodeChunked(bytes("4\r\nPala\r\n")), null);
  const done = decodeChunked(bytes("4\r\nPala\r\n6;x=1\r\nčinke\r\n0\r\n\r\n"));
  assertEquals(new TextDecoder().decode(done!), "Palačinke");
  assertThrows(() => decodeChunked(bytes("zz\r\n")));
  assertThrows(() =>
    decodeChunked(bytes("FFFFF\r\n" + "a".repeat(1_048_575) + "\r\n"))
  );
});

Deno.test({
  name: "transport: chunked telo, preusmerenje i odbijeni odgovori",
  permissions: { net: ["127.0.0.1"] },
  fn: async () => {
    const page = (port: number) =>
      requestPage(
        new URL(`http://recepti.invalid:${port}/a?b=1`),
        "127.0.0.1",
        3000,
      );
    const request = await withRawServer(
      "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nTransfer-Encoding: chunked\r\n\r\n2\r\nok\r\n0\r\n\r\n",
      async (port) => assertEquals((await page(port)).body, "ok"),
    );
    assertEquals(request.startsWith("GET /a?b=1 HTTP/1.1\r\n"), true);
    await withRawServer(
      "HTTP/1.1 301 Moved\r\nLocation: https://drugi.invalid/\r\nContent-Length: 0\r\n\r\n",
      async (port) => {
        const result = await page(port);
        assertEquals([result.status, result.location], [
          301,
          "https://drugi.invalid/",
        ]);
      },
    );
    await withRawServer(
      "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 2\r\n\r\n{}",
      (port) => assertRejects(() => page(port)),
    );
    await withRawServer(
      "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: 2000000\r\n\r\n",
      (port) => assertRejects(() => page(port)),
    );
    await withRawServer(
      "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: 10\r\n\r\nkratko",
      (port) => assertRejects(() => page(port)),
    );
  },
});

Deno.test({
  name: "transport: istek vremena prekida vezu koja ne odgovara",
  permissions: { net: ["127.0.0.1"] },
  fn: async () => {
    const listener = Deno.listen({ hostname: "127.0.0.1", port: 0 });
    const accepted = listener.accept();
    try {
      await assertRejects(
        () =>
          requestPage(
            new URL(
              `http://spor.invalid:${(listener.addr as Deno.NetAddr).port}/`,
            ),
            "127.0.0.1",
            200,
          ),
        Error,
        "timeout",
      );
    } finally {
      (await accepted).close();
      listener.close();
    }
  },
});

Deno.test("tekst recepta dekodira HTML entitete i sažima razmake", () => {
  assertEquals(cleanText("Pizza &amp; Pizza Dough"), "Pizza & Pizza Dough");
  assertEquals(cleanText("Baka&#8217;s  &quot;pita&quot;\n"), 'Baka’s "pita"');
  assertEquals(cleanText("&#x1F355; &nepoznat; &#0;"), "🍕 &nepoznat; &#0;");
  const html =
    `<script type="application/ld+json">{"@type":"Recipe","name":"Pita &amp; jogurt","recipeIngredient":["1&nbsp;kg brašna"],"recipeInstructions":"Umesi &amp; ispeci."}</script>`;
  assertEquals(extractRecipe(html), {
    title: "Pita & jogurt",
    servings: null,
    ingredients: ["1 kg brašna"],
    steps: ["Umesi & ispeci."],
  });
});
