import dataclasses
import io
import unittest

from shelfkit.catalog import Catalog
from shelfkit.cli import main, renderRow, renderTag
from shelfkit.models.product import Product


class HiddenFeature(unittest.TestCase):
    def test_url_path_uses_category_and_name_slugs(self):
        item = Product('Oat Milk 1L', 'Dairy & Eggs', 349)
        self.assertEqual(item.url_path, '/shop/dairy-eggs/oat-milk-1l')

    def test_url_path_trims_and_collapses_like_hyphenate(self):
        item = Product('  Café  Latte!! ', 'Hot   Drinks', 1)
        self.assertEqual(item.url_path, '/shop/hot-drinks/caf-latte')

    def test_price_label_groups_thousands(self):
        self.assertEqual(Product('Espresso Machine', 'Kitchen', 123450).price_label, '$1,234.50')

    def test_price_label_pads_small_and_zero_prices(self):
        self.assertEqual(Product('Sticker', 'Gifts', 5).price_label, '$0.05')
        self.assertEqual(Product('Free Sample', 'Gifts', 0).price_label, '$0.00')

    def test_both_are_read_only_properties_not_fields(self):
        self.assertIsInstance(Product.url_path, property)
        self.assertIsInstance(Product.price_label, property)
        self.assertEqual([f.name for f in dataclasses.fields(Product)], ['name', 'category', 'price_cents'])

    def test_product_validation_is_unchanged(self):
        with self.assertRaises(ValueError):
            Product('', 'Dairy', 1)
        with self.assertRaises(ValueError):
            Product('Milk', ' ', 1)
        with self.assertRaises(ValueError):
            Product('Milk', 'Dairy', -1)

    def test_render_tag_joins_name_price_and_path(self):
        item = Product('Oat Milk 1L', 'Dairy & Eggs', 349)
        self.assertEqual(renderTag(item), 'Oat Milk 1L | $3.49 | /shop/dairy-eggs/oat-milk-1l')

    def test_render_tag_for_a_large_price(self):
        item = Product('Espresso Machine', 'Kitchen', 123450)
        self.assertEqual(renderTag(item), 'Espresso Machine | $1,234.50 | /shop/kitchen/espresso-machine')

    def test_existing_listing_output_is_untouched(self):
        catalog = Catalog()
        catalog.add(Product('Oat Milk 1L', 'Dairy', 349))
        out = io.StringIO()
        self.assertEqual(main(catalog, out), 0)
        self.assertEqual(
            out.getvalue(),
            '%-24s %10s\n%s\n' % ('NAME', 'CENTS', renderRow(Product('Oat Milk 1L', 'Dairy', 349))),
        )
