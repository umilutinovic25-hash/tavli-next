import tempfile
import unittest
from pathlib import Path

from scripts.build_food_catalog_seed import generate

ROOT = Path(__file__).resolve().parent.parent
WORKSHEET = ROOT / "specs/018-ingredient-catalog/research/catalog-review-worksheet.csv"
NUTRITION = (
    ROOT
    / "specs/023-optional-nutrition/research/nutrition-values-sr-legacy-2018.csv"
)


class BuildFoodCatalogSeedTests(unittest.TestCase):
    def test_seed_has_reviewed_catalog_and_only_complete_attributed_values(self):
        with tempfile.TemporaryDirectory() as temp:
            first = Path(temp) / "first.sql"
            second = Path(temp) / "second.sql"
            self.assertEqual(generate(WORKSHEET, NUTRITION, first), (334, 308, 326))
            self.assertEqual(generate(WORKSHEET, NUTRITION, second), (334, 308, 326))
            self.assertEqual(first.read_bytes(), second.read_bytes())
            sql = first.read_text(encoding="utf-8")
            self.assertIn("on conflict do nothing;", sql)
            self.assertIn("SR Legacy 2018-04", sql)
            self.assertIn("manual review confirmed by Uros Milutinovic", sql)


if __name__ == "__main__":
    unittest.main()
