import csv
import tempfile
import unittest
from pathlib import Path
from zipfile import ZipFile

from scripts.build_nutrition_reference_csv import build


class BuildNutritionReferenceCsvTests(unittest.TestCase):
    def test_joins_nutrients_by_fdc_id_and_keeps_missing_as_unknown(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            worksheet = root / "worksheet.csv"
            with worksheet.open("w", newline="", encoding="utf-8") as stream:
                writer = csv.DictWriter(
                    stream,
                    fieldnames=[
                        "candidate_name", "category_hint", "proposed_base_unit",
                        "identity_status", "usda_reviewer", "usda_fdc_id",
                        "usda_description",
                    ],
                )
                writer.writeheader()
                writer.writerows([
                    {
                        "candidate_name": "krompir", "category_hint": "povrće",
                        "proposed_base_unit": "g", "identity_status": "pending",
                        "usda_reviewer": "", "usda_fdc_id": "1",
                        "usda_description": "potato",
                    },
                    {
                        "candidate_name": "kajmak", "category_hint": "mlečno",
                        "proposed_base_unit": "g", "identity_status": "pending",
                        "usda_reviewer": "", "usda_fdc_id": "",
                        "usda_description": "",
                    },
                ])

            archive_path = root / "foods.zip"
            with ZipFile(archive_path, "w") as archive:
                archive.writestr(
                    "sr/food.csv",
                    "fdc_id,data_type,description,food_category_id,publication_date\n"
                    "1,sr_legacy,Potatoes,1,2018-04\n",
                )
                archive.writestr(
                    "sr/food_nutrient.csv",
                    "id,fdc_id,nutrient_id,amount\n"
                    "1,1,1008,77\n2,1,1003,2\n3,1,1004,0.1\n4,1,1005,17\n",
                )

            output = root / "nutrition.csv"
            total, complete = build(worksheet, archive_path, output)
            self.assertEqual((total, complete), (2, 1))
            with output.open(newline="", encoding="utf-8") as stream:
                rows = list(csv.DictReader(stream))
            self.assertEqual(rows[0]["kcal_per_100g"], "77")
            self.assertEqual(rows[0]["nutrition_source_ref"], "FDC 1")
            self.assertEqual(rows[0]["identity_status"], "pending")
            self.assertEqual(rows[1]["kcal_per_100g"], "")
            self.assertEqual(rows[1]["nutrition_source"], "")


if __name__ == "__main__":
    unittest.main()
