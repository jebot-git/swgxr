"""Reconversion must repair a changed content-addressed preview cache."""
import hashlib
from pathlib import Path
import tempfile
import unittest
from prepare_inventory import InventoryImporter, ROOT, native_shared_templates

class InventoryCacheTests(unittest.TestCase):
    def test_loot_alias_follows_native_shared_inheritance(self):
        with tempfile.TemporaryDirectory() as folder:
            core=Path(folder);scripts=core/'MMOCoreORB/bin/scripts/object';scripts.mkdir(parents=True)
            (scripts/'objects.lua').write_text('ObjectTemplates:addClientTemplate(shared_book, "object/tangible/shared_book.iff")')
            (scripts/'loot.lua').write_text('base_book = shared_book:new {}\nquest_book = base_book:new {}\nObjectTemplates:addTemplate(quest_book, "object/tangible/quest_book.iff")')
            inputs={};mapping=native_shared_templates(core, {'object/tangible/quest_book.iff'}, inputs)
            self.assertEqual(mapping, {'object/tangible/quest_book.iff':'object/tangible/shared_book.iff'})
            self.assertEqual(len(inputs),2)
            self.assertTrue(all(len(record['sha256'])==64 for record in inputs.values()))

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
