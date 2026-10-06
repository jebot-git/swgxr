"""Original Ranger descriptions, planet-specific camouflage art and trainer coverage."""
import hashlib
import io
import json
from pathlib import Path
import sys
import unittest
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
sys.path[:0]=[str(ROOT/'tools/assets'),str(ROOT)]
from swg_formats import TreSet
from stf import string_table
from character_formats import datatable


@unittest.skipUnless((ROOT/'runtime/assets/scout/catalog.json').exists(),'Prepared user-provided scout assets required')
class RangerAssets(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalog=json.loads((ROOT/'runtime/assets/scout/catalog.json').read_text())
        cls.tre=TreSet(ROOT/'runtime/assets/active_tre')

    def test_original_descriptions_and_eighteen_skill_boxes_are_preserved(self):
        descriptions=string_table(self.tre.read('string/en/cmd_d.stf'))
        for command,row in self.catalog['commands'].items():
            self.assertEqual(row['description'],descriptions[command])
        skills={row['NAME']:row for row in datatable(self.tre.read('datatables/skill/skills.iff')) if row['NAME'].startswith('outdoors_ranger_')}
        self.assertEqual(len(skills),18)
        self.assertEqual(set(skills),set(self.catalog['ranger_skills']))
        for key,row in self.catalog['ranger_skills'].items():
            self.assertEqual(row['commands'],list(filter(None,skills[key]['COMMANDS'].split(','))))
            self.assertEqual(row['skill_mods'],skills[key]['SKILL_MODS'])
        for source in ('string/en/cmd_d.stf','string/en/skl_d.stf','datatables/skill/skills.iff'):
            self.assertEqual(self.catalog['source_hashes'][source]['sha256'],hashlib.sha256(self.tre.read(source)).hexdigest())

    def test_all_planet_kits_have_ready_original_models_and_exact_native_zone(self):
        kits=self.catalog['camouflage_kits']
        self.assertEqual(len(kits),10)
        self.assertEqual({row['effective_zone'] for row in kits.values()},
                         {'corellia','dantooine','dathomir','endor','lok','naboo','rori','talus','tatooine','yavin4'})
        for template,row in kits.items():
            with self.subTest(template=template):
                self.assertEqual(row['status'],'ready')
                model=(ROOT/'runtime/assets/inventory'/row['inventory_model']).read_bytes()
                self.assertEqual(hashlib.sha256(model).hexdigest(),row['model_sha256'])
                self.assertTrue(row['description'])
                self.assertIn('"'+row['effective_zone']+'"',(ROOT/row['source_script']).read_text())

    def test_new_ability_icons_are_exact_original_atlas_crops(self):
        directory=ROOT/'runtime/combat/abilities'
        icons=json.loads((directory/'catalog.json').read_text())
        for command in ('conceal','rescue','areatrack'):
            row=icons['icons'][command]
            self.assertEqual(row['source_style'],command)
            expected=Image.open(io.BytesIO(self.tre.read(row['source']))).convert('RGBA').crop(tuple(row['source_rect']))
            actual=Image.open(directory/row['path']).convert('RGBA')
            self.assertEqual(actual.size,(24,24))
            self.assertEqual(actual.tobytes(),expected.tobytes())

    def test_tatooine_ranger_trainer_original_appearance_is_prepared(self):
        placements=json.loads((ROOT/'runtime/assets/ambient_npcs/placements.json').read_text())
        catalog=json.loads((ROOT/'runtime/assets/ambient_npcs/catalog.json').read_text())
        trainers=[r for r in placements['instances'] if r.get('mobile')=='trainer_ranger']
        self.assertTrue(trainers)
        for row in trainers:
            descriptor=catalog['races'][row.get('appearance_id',row['template'])]
            self.assertTrue(descriptor['appearance_complete'])
        self.assertEqual(self.catalog['failures'],[])


if __name__=='__main__': unittest.main()
