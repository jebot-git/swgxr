"""Broken CDF names resolve only through verified original appearance metadata."""
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools/assets'))
from npc_reference_repairs import resolve_cdf_mesh, TABLE
from prepare_characters import CharacterImporter
from character_formats import datatable
from swg_formats import parse_iff, cstring


@unittest.skipUnless((ROOT/'runtime/asset_sources/active_tre').exists(), 'Supplied TREs required')
class NpcReferenceRepairs(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory()
        cls.importer = CharacterImporter(ROOT/'runtime/asset_sources/active_tre', Path(cls.temporary.name))

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def test_only_authored_table_and_sat_confirmed_paths_are_repaired(self):
        cases = [
            ('appearance/mesh/hat_s04_hum_f.lmg', 'appearance/hum_f.sat',
             'clientdata/npc/client_shared_npc_dressed_tatooine_valarian_swooper_leader.cdf',
             'appearance/mesh/hat_s04_f.lmg'),
            ('appearance/mesh/armor_chitin_s01_gloves.lmg', 'appearance/zab_m.sat',
             'clientdata/npc/client_shared_npc_dressed_tatooine_desert_demon.cdf',
             'appearance/mesh/armor_chitin_s01_gloves_m.lmg'),
            ('appearance/mesh/armor_chitin_s01_gloves.lmg', 'appearance/hum_m.sat',
             'clientdata/npc/client_shared_npc_dressed_tatooine_desert_demon_leader.cdf',
             'appearance/mesh/armor_chitin_s01_gloves_m.lmg')]
        rows = datatable(self.importer.read(TABLE))
        for source, owner, cdf, expected in cases:
            resolved, record = resolve_cdf_mesh(self.importer, source, owner, cdf)
            self.assertEqual(resolved, expected)
            self.assertNotIn(source, self.importer.t.entries)
            row = next(row for row in rows if row['Object Template Name'] == record['table_row'])
            self.assertEqual(row[record['table_column']], record['mapped_appearance'])
            self.assertEqual(parse_iff(self.importer.read(record['mapped_appearance'])).first('MSGN').data,
                             (resolved+'\0').encode())
            self.assertIn(resolved, self.importer.dependencies)

    def test_missing_gender_hair_or_unrelated_cdf_never_gets_a_substitute(self):
        for source, owner, cdf in [
            ('appearance/mesh/gloves_tusken_raider_f.lmg','appearance/hum_f.sat',
             'clientdata/npc/client_shared_npc_dressed_corsair_cutthroat_hum_f.cdf'),
            ('appearance/mesh/twk_f_hair_s10.lmg','appearance/twk_f.sat',
             'clientdata/npc/client_shared_npc_dressed_rebel_recruiter_twilek_female_01.cdf'),
            ('appearance/mesh/hat_s04_hum_f.lmg','appearance/zab_m.sat',
             'clientdata/npc/client_shared_npc_dressed_tatooine_valarian_swooper_leader.cdf'),
            ('appearance/mesh/armor_chitin_s01_gloves.lmg','appearance/hum_m.sat','unrelated.cdf')]:
            self.assertEqual(resolve_cdf_mesh(self.importer, source, owner, cdf), (source, None))
        glove = next(row for row in datatable(self.importer.read(TABLE))
                     if row['Object Template Name'] == 'shared_gloves_tusken_raider')
        self.assertEqual(glove['Female Human'], 'x')

    def test_prepared_base_and_weapon_variant_keep_repairs_and_original_identity(self):
        cases = [('ambient_npcs', 'object/mobile/dressed_tatooine_valarian_swooper_leader.iff'),
                 ('ambient_npcs', 'object/mobile/dressed_tatooine_desert_demon.iff'),
                 ('ambient_npcs', 'object/mobile/dressed_tatooine_desert_demon.iff#weapon=object/weapon/ranged/pistol/pistol_dl44.iff'),
                 ('combat_population/tatooine', 'object/mobile/dressed_tatooine_desert_demon_leader.iff')]
        for directory, template in cases:
            directory = ROOT/'runtime/assets'/directory
            if not (directory/'catalog.json').exists():
                self.skipTest('Prepared NPC catalogs required')
            catalog = json.loads((directory/'catalog.json').read_text())
            descriptor = catalog['races'][template]
            self.assertTrue(descriptor['appearance_complete'], template)
            repaired = [row for row in descriptor['default_outfit'] if row.get('source_reference_repair')]
            self.assertEqual(len(repaired), 1, template)
            item = repaired[0]; record = item['source_reference_repair']
            self.assertEqual(item['template'], record['original_reference'])
            self.assertEqual(item['appearance'], record['resolved_reference'])
            model = json.loads((directory/item['model']).read_text())
            original_mgn = cstring(parse_iff(self.importer.read(item['appearance'])).first('NAME').data)[0]
            self.assertEqual(model['parts'][0]['mesh']['source'], original_mgn)
            self.assertTrue(model['parts'][0]['mesh']['surfaces'][0]['indices'])
            for source in (TABLE, record['mapped_appearance'], record['resolved_reference'], original_mgn):
                self.assertIn(source, catalog['provenance']['dependencies'])

    def test_missing_cdf_keeps_the_original_medic_body_and_explicit_partial_status(self):
        directory = ROOT/'runtime/assets/combat_population/tatooine'
        if not (directory/'catalog.json').exists():
            self.skipTest('Prepared NPC catalog required')
        catalog = json.loads((directory/'catalog.json').read_text())
        descriptor = catalog['races']['object/mobile/dressed_rebel_medic2_21b_01.iff']
        self.assertFalse(descriptor['appearance_complete'])
        self.assertEqual(descriptor['default_outfit'], [])
        self.assertTrue(descriptor['appearance_failures'])
        self.assertEqual(descriptor['appearance_failures'][0]['phase'], 'client_data')
        self.assertNotIn(descriptor['source_cdf'], self.importer.t.entries)
        body = json.loads((directory/descriptor['body']).read_text())
        self.assertEqual(body['appearance'], self.importer.appearance(descriptor['shared_template']))
        self.assertTrue(body['parts'][0]['mesh']['surfaces'])


if __name__ == '__main__':
    unittest.main()
