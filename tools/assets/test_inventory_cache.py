"""Reconversion must repair a changed content-addressed preview cache."""
import hashlib
from pathlib import Path
import tempfile
import unittest
from prepare_inventory import InventoryImporter, ROOT

class InventoryCacheTests(unittest.TestCase):
    def test_reconversion_repairs_cached_bytes_before_publishing_hash(self):
        with tempfile.TemporaryDirectory() as folder:
            importer=InventoryImporter(ROOT/'runtime/asset_sources/active_tre',Path(folder))
            template='object/weapon/ranged/pistol/pistol_cdef.iff'
            first=importer.convert(template)
            self.assertEqual(first['status'],'ready',first['failures'])
            model=Path(folder)/first['model'];original=model.read_bytes()
            model.write_bytes(original+b' ')
            second=importer.convert(template)
            self.assertEqual(second['status'],'ready',second['failures'])
            self.assertEqual(second['model'],first['model'])
            self.assertEqual(model.read_bytes(),original)
            self.assertEqual(hashlib.sha256(model.read_bytes()).hexdigest(),second['model_sha256'])

if __name__=='__main__':unittest.main()
