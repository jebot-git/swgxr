"""Actual supplied-media rewards and NPC coverage, with explicit source omissions."""
import hashlib
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools/assets'))
from prepare_gcw import PERKS, reward_rows
from stf import string_table
from swg_formats import TreSet


class GcwAssets(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalog = json.loads((ROOT / 'runtime/assets/gcw/catalog.json').read_text())
        cls.inventory = json.loads((ROOT / 'runtime/assets/inventory/catalog.json').read_text())
        cls.npcs = json.loads((ROOT / 'runtime/assets/ambient_npcs/catalog.json').read_text())
        cls.media = TreSet(ROOT / 'runtime/asset_sources/active_tre')

    def test_original_ordered_rewards_exclude_unlisted_and_campaign_content(self):
        rewards = self.catalog['rewards']
        self.assertEqual(len(rewards), 54)
        self.assertEqual({r['faction'] for r in rewards}, {'rebel', 'imperial'})
        self.assertEqual({r['category'] for r in rewards}, {'weaponsArmor', 'uniforms', 'furniture'})
        # The native table has a broken, unused metal_staff row and an unlisted
        # Imperial backpack. Neither belongs in the original shopping lists.
        self.assertNotIn('metal_staff', {r['key'] for r in rewards})
        self.assertNotIn('imperial:weaponsArmor:armor_stormtrooper_backpack', {r['id'] for r in rewards})
        self.assertEqual([r['key'] for r in rewards if r['faction'] == 'imperial' and r['category'] == 'uniforms'],
                         ['boots_s14', 'hat_imp_s01', 'jacket_s03', 'pants_s15'])
        self.assertEqual(reward_rows((ROOT / PERKS).read_text())[0]['base_cost'], 1500)

    def test_all_rewards_have_source_labels_and_verified_original_models(self):
        for reward in self.catalog['rewards']:
            table, key = reward['display_stf'][1:].split(':')
            self.assertEqual(reward['name'], string_table(self.media.read('string/en/' + table + '.stf'))[key])
            self.assertEqual(reward['preview_status'], 'ready')
            item = self.inventory['items'][reward['template']]
            self.assertEqual(item['model'], reward['preview_model'])
            raw = (ROOT / 'runtime/assets/inventory' / reward['preview_model']).read_bytes()
            self.assertEqual(hashlib.sha256(raw).hexdigest(), reward['preview_sha256'])
            self.assertGreater(len(json.loads(raw)['surfaces']), 0)

    def test_source_provenance_and_known_missing_recruiter_headpiece(self):
        for path, entry in self.catalog['source_hashes'].items():
            raw = (ROOT / path).read_bytes() if path.startswith('vendor/') else self.media.read(path)
            self.assertEqual(hashlib.sha256(raw).hexdigest(), entry['sha256'], path)
        failures = self.catalog['failures']
        self.assertEqual(len(failures), 1)
        self.assertEqual(failures[0]['resource'], 'appearance/mesh/twk_f_hair_s10.lmg')
        self.assertNotIn(failures[0]['resource'], self.media.entries)
        self.assertFalse(self.catalog['npc_appearances'][failures[0]['template']]['complete'])

    def test_npc_bodies_and_existing_moods_survive_incremental_preparation(self):
        appearances = self.catalog['npc_appearances']
        self.assertEqual(len(appearances), 44)
        self.assertIn('object/creature/npc/theme_park/lambda_shuttle.iff', appearances)
        self.assertTrue(all(row['ready'] for row in appearances.values()))
        for body in {row['body'] for row in appearances.values()}:
            model = json.loads((ROOT / 'runtime/assets/ambient_npcs' / body).read_text())
            self.assertTrue(model['bones'])
            for actor in self.npcs['races'].values():
                if actor['body'] != body:
                    continue
                for mood in actor.get('mood_animations', {}).values():
                    self.assertIn(mood, set(model['animations']), actor['template'])

    def test_native_runtime_package_carries_gcw_metadata(self):
        from tools.deploy.package_runtime import REQUIRED_ASSET_CATALOGS
        self.assertIn('runtime/assets/gcw/catalog.json', REQUIRED_ASSET_CATALOGS)

    def test_crackdown_carrier_has_original_ground_and_flight_clips(self):
        row = self.npcs['races']['object/creature/npc/theme_park/lambda_shuttle.iff']
        model = json.loads((ROOT / 'runtime/assets/ambient_npcs' / row['body']).read_text())
        for state, logical, loop in [('land', 'land', False), ('takeoff', 'takeoff', False),
                                     ('ground', 'loop_ground', True), ('sky', 'loop_sky', True)]:
            entry = model['animation_library']['carrier_' + state]
            clip = json.loads((ROOT / 'runtime/assets/ambient_npcs' / entry['path']).read_text())
            self.assertEqual(clip['logical'], logical)
            self.assertEqual(clip['loop'], loop)
            self.assertTrue(clip['tracks'])
            self.assertIn(clip['source'], self.npcs['provenance']['dependencies'])

    def test_crackdown_carrier_includes_every_original_cdf_rigid_child(self):
        from swg_formats import parse_iff, cstring
        row = self.npcs['races']['object/creature/npc/theme_park/lambda_shuttle.iff']
        expected = set()
        for node in parse_iff(self.media.read(row['source_cdf'])).walk('HOBJ'):
            appearance, pos = cstring(node.data)
            expected.add((appearance, cstring(node.data, pos)[0]))
        actual = row['rigid_equipment']
        self.assertEqual(len(expected), 11)
        self.assertEqual({(a['appearance'], a['bone']) for a in actual}, expected)
        triangles = 0
        for child in actual:
            model = json.loads((ROOT / 'runtime/assets/ambient_npcs' / child['model']).read_text())
            triangles += sum(len(s['indices']) // 3 for s in model['surfaces'])
            self.assertIn(child['appearance'], self.npcs['provenance']['dependencies'])
        self.assertGreater(triangles, 3000, 'Glass-only skinned mesh is not the complete shuttle')


if __name__ == '__main__':
    unittest.main()
