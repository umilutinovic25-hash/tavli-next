import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import { parseCurrentPriceList } from "./prices.ts";

const source = {
  sourceId: "delhaize" as const,
  retailer: "Delhaize Serbia",
  url: "https://example.com/prices.csv",
  downloadUrl: "https://example.com/prices.csv",
};

const csv = (body: string) => new TextEncoder().encode(body);

Deno.test("parses quoted semicolon CSV, Serbian decimals and current rows", async () => {
  const result = await parseCurrentPriceList(
    csv(
      "BARKOD;NAZIV_PROIZVODA;JEDINICA_MERE;NAZIV TRGOVCA – FORMATA;DATUM_CENOVNIKA;REDOVNA_CENA;VRSTA_CENOVNIKA\n" +
        '123;"Mleko; punomasno";lit;Maxi;21.11.2026;123,45;VAZECI_CENOVNIK\n' +
        "124;Stari proizvod;kg;Maxi;01.11.2026;99,00;MESECNI_PRESEK\n",
    ),
    source,
  );

  assertEquals(result.rows.length, 1);
  assertEquals(result.rows[0], {
    retailer: "Delhaize Serbia",
    retailerFormat: "Maxi",
    barcode: "123",
    productName: "Mleko; punomasno",
    measure: "lit",
    priceListType: "VAZECI_CENOVNIK",
    priceDate: "2026-11-21",
    regularPriceParas: 12345,
    rowSha256: result.rows[0].rowSha256,
  });
  assertEquals(result.sourceSha256.length, 64);
});

Deno.test("rejects malformed or unrecognized schemas and guessed price formats", async () => {
  await assertRejects(
    () => parseCurrentPriceList(csv("header\nvalue\n"), source),
    Error,
    "unsupported_csv_schema",
  );
  await assertRejects(
    () =>
      parseCurrentPriceList(
        csv(
          "BARKOD;NAZIV_PROIZVODA;JEDINICA_MERE;TRGOVAC_FORMAT;DATUM_CENOVNIKA;REDOVNA_CENA;VRSTA_CENOVNIKA\n" +
            "123;Mleko;lit;Maxi;2026-11-21;12.345;VAZECI_CENOVNIK\n",
        ),
        source,
      ),
    Error,
    "invalid_regular_price",
  );
});

Deno.test("rejects incomplete quoted CSV and empty current price lists", async () => {
  await assertRejects(
    () => parseCurrentPriceList(csv('"unfinished;field'), source),
    Error,
    "unterminated_quoted_field",
  );
  await assertRejects(
    () =>
      parseCurrentPriceList(
        csv(
          "BARKOD;NAZIV_PROIZVODA;JEDINICA_MERE;TRGOVAC_FORMAT;DATUM_CENOVNIKA;REDOVNA_CENA;VRSTA_CENOVNIKA\n" +
            "123;Staro;kg;Maxi;2026-11-01;99,00;MESECNI_PRESEK\n",
        ),
        source,
      ),
    Error,
    "no_current_price_rows",
  );
});
