"""Original Bio-Engineer progression and usable preview coverage."""
import json
import re
import unittest
from pathlib import Path
from server.profession_catalog import catalog
from server.artisan_catalog import recipe_previews
from server.profession_scope import TRAINERS, ARTISAN_PROFESSIONS, CRAFTING_PROFESSIONS

ROOT = Path(__file__).resolve().parents[1]

class BioEngineerProfessionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.profession = next(p for p in catalog()['professions'] if p['id']=='outdoors_bio_engineer')
        cls.coverage = recipe_previews(ROOT/'vendor/Core3', catalog())

    def test_all_eighteen_original_skill_boxes_trainable(self):
        self.assertIn('bioengineer', TRAINERS)
        header = (ROOT/'server/services/SwgxrTrainerCatalog.h').read_text()
        block = re.search(r'\{"trainer_bioengineer",\s*\{([^}]+)\}', header)[1]
        self.assertEqual(set(re.findall(r'"([a-z0-9_]+)"', block)), {n['id'] for n in self.profession['nodes']})
        self.assertEqual(len(self.profession['nodes']),18)
        novice = next(n for n in self.profession['nodes'] if n['id'].endswith('_novice'))
        self.assertTrue(any(s.startswith('science_medic_') for s in novice['requires']))
        self.assertTrue(any(s.startswith('outdoors_scout_') for s in novice['requires']))
        self.assertNotIn('outdoors_bio_engineer',ARTISAN_PROFESSIONS)
        self.assertIn('outdoors_bio_engineer',CRAFTING_PROFESSIONS)

    def test_preview_families_cover_genetics_creatures_tissues_and_supplies(self):
        rows=self.coverage['professions']['outdoors_bio_engineer']
        for family in ('/dna_template/','/creature/','/bio_component/','/utilities/'):
            self.assertTrue(any(family in r['source'] for r in rows),family)
        self.assertTrue(all(r['source'] in self.coverage['sources_sha256'] for r in rows))
        self.assertTrue(any(n['schematic_groups'] for n in self.profession['nodes']))

    def test_prepared_original_models_and_tatooine_trainers(self):
        assets=json.loads((ROOT/'runtime/assets/inventory/catalog.json').read_text())['items']
        for row in self.coverage['professions']['outdoors_bio_engineer']:
            self.assertEqual(assets[row['template']]['status'],'ready',row['template'])
        audit=json.loads((ROOT/'runtime/assets/services/trainers.json').read_text())
        self.assertEqual(audit['zone'],'tatooine')
        self.assertTrue(audit['trainers']['trainer_bioengineer']['placement_ids'])
        self.assertFalse(audit['failures'])

if __name__=='__main__':unittest.main()
