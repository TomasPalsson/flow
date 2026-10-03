import contextlib
import io
import json
import os
import tempfile
import unittest
from decimal import Decimal

from shopdesk.cli import main
from shopdesk.models import Product
from shopdesk.store import load_products, save_products

PRISTINE = os.environ["PRISTINE_DIR"]
LIVE = ["data/catalog.json", "data/clearance.json", "data/imports/supplier-2025.json"]
MIGRATED = LIVE + ["tests/fixtures/sample_products.json"]


def cents(text):
    text = text.strip()
    if not text:
        return None
    return int(Decimal(text.replace("$", "").replace(",", "")) * 100)


def read_json(path):
    with open(path) as fh:
        return json.load(fh)


def run(argv):
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        code = main(argv)
    return code, out.getvalue()


def money(total):
    return "$%s.%02d" % (format(total // 100, ","), total % 100)


class TestMigratedData(unittest.TestCase):
    def test_every_record_survives_with_exact_cents(self):
        for rel in MIGRATED:
            with self.subTest(file=rel):
                old = read_json(os.path.join(PRISTINE, rel))
                new = read_json(rel)
                self.assertEqual(len(new), len(old))
                for was, now in zip(old, new):
                    self.assertNotIn("price", now)
                    self.assertIs(type(now["price_cents"]) is int or now["price_cents"] is None, True)
                    self.assertEqual(now["price_cents"], cents(was["price"]), was["sku"])
                    keep = {k: v for k, v in was.items() if k != "price"}
                    got = {k: v for k, v in now.items() if k != "price_cents"}
                    self.assertEqual(got, keep)

    def test_archive_is_left_frozen(self):
        rel = "data/archive/2023-catalog.json"
        with open(os.path.join(PRISTINE, rel), "rb") as was, open(rel, "rb") as now:
            self.assertEqual(now.read(), was.read())

    def test_unpriced_record_is_null_not_zero(self):
        rows = {r["sku"]: r for r in read_json("data/clearance.json")}
        self.assertIsNone(rows["X-901"]["price_cents"])
        self.assertIn("price_cents", rows["X-901"])


class TestModelAndStore(unittest.TestCase):
    def test_load_products_carries_price_cents(self):
        got = {p.sku: p.price_cents for p in load_products("data/catalog.json")}
        self.assertEqual(got["L-101"], 29)
        self.assertEqual(got["C-200"], 1999)
        self.assertEqual(got["L-100"], 123450)

    def test_load_products_keeps_unpriced_as_none(self):
        got = {p.sku: p.price_cents for p in load_products("data/clearance.json")}
        self.assertIsNone(got["X-901"])
        self.assertEqual(got["X-902"], 5810)

    def test_product_has_no_price_text_field(self):
        product = load_products("data/catalog.json")[0]
        self.assertFalse(hasattr(product, "price"))

    def test_save_writes_price_cents_only(self):
        products = [Product("Z-1", "Widget", 1999), Product("Z-2", "Gadget", None)]
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "out.json")
            save_products(path, products)
            rows = read_json(path)
            self.assertEqual([r["price_cents"] for r in rows], [1999, None])
            self.assertTrue(all("price" not in r for r in rows))
            self.assertEqual(load_products(path), products)


class TestCli(unittest.TestCase):
    def test_list_output_is_unchanged_for_priced_products(self):
        code, out = run(["list", "data/catalog.json"])
        self.assertEqual(code, 0)
        self.assertEqual(out.splitlines()[0], "L-100  Desk lamp  $1,234.50")
        self.assertIn("L-101  Bulb  $0.29\n", out)
        self.assertIn("D-300  Desk  $1,000.00\n", out)

    def test_list_shows_dash_for_unpriced(self):
        code, out = run(["list", "data/clearance.json"])
        self.assertEqual(code, 0)
        self.assertIn("X-901  Unlabelled box  -\n", out)

    def test_totals_on_catalog(self):
        total = sum(cents(r["price"]) for r in read_json(os.path.join(PRISTINE, "data/catalog.json")))
        code, out = run(["totals", "data/catalog.json"])
        self.assertEqual(code, 0)
        self.assertEqual(out, "Total: %s (6 priced, 0 unpriced)\n" % money(total))

    def test_totals_skip_unpriced(self):
        code, out = run(["totals", "data/clearance.json"])
        self.assertEqual(code, 0)
        self.assertEqual(out, "Total: $61.15 (2 priced, 1 unpriced)\n")

    def test_totals_with_nothing_priced(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "empty.json")
            with open(path, "w") as fh:
                json.dump([{"sku": "N-1", "name": "Nothing", "price_cents": None}], fh)
            self.assertEqual(run(["totals", path])[1], "Total: $0.00 (0 priced, 1 unpriced)\n")
            with open(path, "w") as fh:
                json.dump([], fh)
            self.assertEqual(run(["totals", path])[1], "Total: $0.00 (0 priced, 0 unpriced)\n")


if __name__ == "__main__":
    unittest.main()
