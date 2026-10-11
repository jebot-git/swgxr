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

    def test_wearable_races_follow_native_inheritance_and_overrides(self):
        with tempfile.TemporaryDirectory() as folder:
            core=Path(folder);scripts=core/'MMOCoreORB/bin/scripts/object';scripts.mkdir(parents=True)
            (scripts/'objects.lua').write_text('ObjectTemplates:addClientTemplate(shared_boots, "object/tangible/shared_boots.iff")')
            (scripts/'boots.lua').write_text('base_boots = shared_boots:new { playerRaces = { "object/creature/player/rodian_male.iff" } }\nquest_boots = base_boots:new {}\nObjectTemplates:addTemplate(quest_boots, "object/tangible/quest_boots.iff")\nall_boots = base_boots:new { playerRaces = {} }\nObjectTemplates:addTemplate(all_boots, "object/tangible/all_boots.iff")')
            rules={};mapping=native_shared_templates(core, {'object/tangible/quest_boots.iff','object/tangible/all_boots.iff'}, {}, rules)
            self.assertEqual(len(mapping),2)
            self.assertEqual(rules['object/tangible/quest_boots.iff'],['object/creature/player/rodian_male.iff'])
            self.assertEqual(rules['object/tangible/all_boots.iff'],[])

    def test_equipment_importer_keeps_owner_materials_and_repairs_cache(self):
        with tempfile.TemporaryDirectory() as folder:
            importer=InventoryImporter(ROOT/'runtime/asset_sources/active_tre',Path(folder))
            template='object/tangible/wearables/armor/zam/armor_zam_wesell_boots.iff'
            shared=template.replace('/armor_zam_', '/shared_armor_zam_')
            human=importer.equipment(template,shared,'human_male')
            rodian=importer.equipment(template,shared,'rodian_male')
            self.assertEqual(human['status'],'ready',human['failures'])
            self.assertEqual(rodian['status'],'ready',rodian['failures'])
            self.assertNotEqual(human['source_owner_shader'],rodian['source_owner_shader'])
            self.assertIsNot(importer.equipment_importers['human_male'],importer.equipment_importers['rodian_male'])
            self.assertIs(importer.equipment_importers['rodian_male'].t,importer.character.t)
            self.assertTrue(importer.reusable_equipment(rodian,shared,'rodian_male'))
            path=Path(folder)/rodian['model'];original=path.read_bytes();path.write_bytes(original+b' ')
            self.assertFalse(importer.reusable_equipment(rodian,shared,'rodian_male'))
            restored=importer.equipment(template,shared,'rodian_male')
            self.assertEqual(restored['model_sha256'],hashlib.sha256(path.read_bytes()).hexdigest())
            self.assertEqual(path.read_bytes(),original)

    def test_twilek_hat_uses_owners_lekku_shader(self):
        import json
        with tempfile.TemporaryDirectory() as folder:
            importer=InventoryImporter(ROOT/'runtime/asset_sources/active_tre',Path(folder))
            template='object/tangible/wearables/hat/hat_twilek_s01.iff'
            shared=template.replace('/hat_twilek', '/shared_hat_twilek')
            for sex in ['male','female']:
                result=importer.equipment(template,shared,'twilek_'+sex)
                self.assertEqual(result['status'],'ready',result['failures'])
                model=json.loads((Path(folder)/result['model']).read_text())
                owners={surface.get('resolved_skin_shader') for part in model['parts'] for surface in part['mesh']['surfaces'] if surface['shader']=='shader/skin_leccu.sht'}
                self.assertEqual(owners,{'shader/twk_'+sex[0]+'_leccu.sht'})

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
