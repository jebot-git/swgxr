"""Source alignment across specialist trees, trainers and original recipe previews."""
import re
import unittest
from pathlib import Path
from server.artisan_catalog import recipe_previews
from server.profession_catalog import catalog
from server.profession_scope import ARTISAN_TRAINERS, ARTISAN_PROFESSIONS

ROOT = Path(__file__).resolve().parents[1]


class ArtisanProfessionsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalog = catalog()
        cls.coverage = recipe_previews(ROOT/'vendor/Core3', cls.catalog)

    def test_all_source_artisan_descendants_have_exact_trainer_nodes(self):
        source = (ROOT/'server/services/SwgxrTrainerCatalog.h').read_text()
        descendants = set()
        for profession in self.catalog['professions']:
            novice = next((n for n in profession['nodes'] if n['id']==profession['id']+'_novice'), {})
            if any(p.startswith('crafting_artisan_') for p in novice.get('requires', [])):
                descendants.add(profession['id'])
        self.assertEqual(descendants, set(ARTISAN_PROFESSIONS)-{'crafting_artisan'})
        for name in ARTISAN_TRAINERS:
            profession = next(p for p in self.catalog['professions'] if p['id']=='crafting_'+name)
            block = re.search(r'\{"trainer_'+name+r'",\s*\{([^}]+)\}', source)[1]
            self.assertEqual(set(re.findall(r'"([a-z0-9_]+)"', block)), {n['id'] for n in profession['nodes']})
            self.assertTrue(all(n['points']>0 and n['credits']>0 for n in profession['nodes']))

    def test_specialist_preview_coverage_without_inventing_merchant_recipes(self):
        for key in ARTISAN_PROFESSIONS:
            rows = self.coverage['professions'][key]
            if key=='crafting_merchant':
                self.assertEqual(rows, [])
                continue
            self.assertGreater(len(rows), 0, key)
            self.assertTrue(all(row['template'].startswith('object/') for row in rows))
        self.assertTrue(any(r['assembly_skill']=='weapon_assembly' for r in self.coverage['professions']['crafting_weaponsmith']))
        self.assertTrue(any(r['assembly_skill']=='clothing_assembly' for r in self.coverage['professions']['crafting_tailor']))
        self.assertTrue(any(r['assembly_skill']=='chassis_assembly' for r in self.coverage['professions']['crafting_shipwright']))
        self.assertTrue(self.coverage['sources_sha256'])

    def test_schematic_grants_are_source_data_not_automatic_unlocks(self):
        for name in ARTISAN_TRAINERS:
            profession = next(p for p in self.catalog['professions'] if p['id']=='crafting_'+name)
            if name!='merchant':
                self.assertTrue(any(n['schematic_groups'] for n in profession['nodes']), name)
        self.assertTrue(self.catalog['read_only'])


if __name__=='__main__': unittest.main()
