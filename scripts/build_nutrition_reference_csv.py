#!/usr/bin/env python3
"""Join catalog review proposals to USDA SR Legacy nutrient references.

This creates a review artifact only. It never writes application seeds or
changes catalog review states.
"""

from __future__ import annotations

import argparse
import csv
from pathlib import Path
from zipfile import ZipFile

NUTRIENTS = {
    "1008": "kcal_per_100g",
    "1003": "protein_grams_per_100g",
    "1004": "fat_grams_per_100g",
    "1005": "carbs_grams_per_100g",
}
VERSION = "SR Legacy 2018-04"
SOURCE = "USDA FoodData Central"
LICENSE = "CC0 1.0"


def read_csv(archive: ZipFile, suffix: str) -> list[dict[str, str]]:
    name = next(n for n in archive.namelist() if n.endswith("/" + suffix))
    with archive.open(name) as stream:
        return list(csv.DictReader(line.decode("utf-8-sig") for line in stream))


def build(worksheet: Path, archive_path: Path, output: Path) -> tuple[int, int]:
    with ZipFile(archive_path) as archive:
        foods = {r["fdc_id"]: r for r in read_csv(archive, "food.csv")}
        nutrients: dict[str, dict[str, str]] = {}
        for row in read_csv(archive, "food_nutrient.csv"):
            target = NUTRIENTS.get(row["nutrient_id"])
            if target and row["amount"].strip():
                nutrients.setdefault(row["fdc_id"], {})[target] = row["amount"]

    with worksheet.open(newline="", encoding="utf-8-sig") as stream:
        catalog = list(csv.DictReader(stream))
    output.parent.mkdir(parents=True, exist_ok=True)
    fields = [
        "candidate_name", "category_hint", "proposed_base_unit",
        "identity_status", "usda_reviewer", "usda_fdc_id",
        "usda_description", *NUTRIENTS.values(), "nutrition_source",
        "nutrition_source_version", "nutrition_source_ref", "license",
    ]
    mapped_and_complete = 0
    with output.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        for row in catalog:
            fdc_id = row["usda_fdc_id"].strip()
            food = foods.get(fdc_id, {}) if fdc_id else {}
            values = nutrients.get(fdc_id, {}) if fdc_id else {}
            complete = all(values.get(field) for field in NUTRIENTS.values())
            mapped_and_complete += bool(complete)
            writer.writerow({
                "candidate_name": row["candidate_name"],
                "category_hint": row["category_hint"],
                "proposed_base_unit": row["proposed_base_unit"],
                "identity_status": row["identity_status"],
                "usda_reviewer": row["usda_reviewer"],
                "usda_fdc_id": fdc_id,
                "usda_description": food.get("description", row["usda_description"]),
                **{field: values.get(field, "") for field in NUTRIENTS.values()},
                "nutrition_source": SOURCE if complete else "",
                "nutrition_source_version": VERSION if complete else "",
                "nutrition_source_ref": f"FDC {fdc_id}" if complete else "",
                "license": LICENSE if complete else "",
            })
    return len(catalog), mapped_and_complete


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("worksheet", type=Path)
    parser.add_argument("sr_legacy_zip", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    total, complete = build(args.worksheet, args.sr_legacy_zip, args.output)
    print(f"Rows: {total}; mapped with all four values: {complete} ({complete / total:.1%})")


if __name__ == "__main__":
    main()
