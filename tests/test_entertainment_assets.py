"""Actual user-media performance coverage and shared particle parser regression."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('entertainment_asset_prep', ROOT/'tools/entertainment/prepare_assets.py')
prep = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prep)


@unittest.skipUnless((ROOT/'runtime/asset_sources/active_tre').exists(), 'User-provided TREs required')
class OriginalEntertainmentAssets(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.assets = prep.Assets(ROOT/'runtime/asset_sources/active_tre', Path(cls.temp.name), bounded_particle_graphs=True)
        cls.failures = prep.prepare_effects(cls.assets)

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def test_all_original_effect_variants_keep_visible_source_emitters(self):
        self.assertEqual(self.failures, [])
        self.assertEqual(len(self.assets.effects), 21)
        for source, effect in self.assets.effects.items():
            with self.subTest(source=source):
                self.assertTrue(effect['appearances'])
                self.assertTrue(any(self.assets.particles[a['particle']]['emitters'] for a in effect['appearances']))
                self.assertTrue(effect['omitted_camera_shake_for_xr'])
                self.assertEqual(self.assets.dependencies[source]['sha256'], hashlib.sha256(self.assets.read(source)).hexdigest())

    def test_old_emitter_and_attachment_sources_decode_without_replacement(self):
        dazzle = self.assets.particles['appearance/pt_entertainer_dazzle.prt']
        self.assertEqual([e['name'] for e in dazzle['emitters']], ['sparks','fire'])
        self.assertTrue(all(e['visible'] and e['curves']['life']['points'] for e in dazzle['emitters']))
        distract = self.assets.particles['appearance/pt_entertainer_distract.prt']
        self.assertTrue(any(o['reason']=='attachment_motion_flattened' for o in distract['bounded_omissions']))
        child = self.assets.particles['appearance/pt_trailing_entertainer_distract_fullsmoke.prt']
        self.assertEqual(distract['emitters'], child['emitters'])
        self.assertTrue(all(e['material']['texture'] for e in distract['emitters']))

    def test_mesh_omission_is_explicit_and_does_not_discard_colorlight_quads(self):
        effect = self.assets.particles['appearance/pt_entertainer_colorlights.prt']
        self.assertIn({'emitter':'ball','reason':'non_quad_particle'}, effect['bounded_omissions'])
        self.assertIn('beams', [e['name'] for e in effect['emitters']])
        self.assertIn('sparkles', [e['name'] for e in effect['emitters']])
        strict = prep.Assets(ROOT/'runtime/asset_sources/active_tre', Path(self.temp.name))
        with self.assertRaisesRegex(ValueError, 'non-quad'):
            strict.particle('appearance/pt_entertainer_colorlights.prt')

    def test_previously_prepared_combat_particles_do_not_change(self):
        path = ROOT/'runtime/assets/combat/assets.json'
        if not path.exists(): self.skipTest('Prepared combat catalog required')
        combat = json.loads(path.read_text())
        importer = prep.Assets(ROOT/'runtime/asset_sources/active_tre', Path(self.temp.name), bounded_particle_graphs=True)
        for source, original in combat['particles'].items():
            with self.subTest(source=source):
                importer.particle(source)
                current = json.loads(json.dumps(importer.particles[source]))
                # The existing cache predates extra shader audit metadata. The
                # decoded emitter and every prior material property must match.
                for emitter, prior in zip(current['emitters'], original['emitters']):
                    for key in ('alpha_source', 'alpha_schema_version'):
                        if key not in prior['material']: emitter['material'].pop(key, None)
                self.assertEqual(current, original)

    def test_prepared_advanced_performances_have_every_rig_and_flourish(self):
        path = ROOT/'runtime/assets/entertainment/catalog.json'
        if not path.exists(): self.skipTest('Prepared entertainment catalog required')
        data = json.loads(path.read_text())
        source = prep.catalog()
        self.assertEqual(set(data['performances']), set(source['performances']))
        expected = {'perform_'+p['animation']+('_'+str(i) if i else '')
                    for p in source['performances'].values() for i in range(9)}
        for race, clips in data['rigs'].items():
            with self.subTest(race=race):
                self.assertEqual(set(clips), expected)
                self.assertTrue(all((path.parent/clip['path']).is_file() for clip in clips.values()))


@unittest.skipUnless((ROOT/'runtime/asset_sources/active_tre').exists(), 'User-provided TREs required')
class PropFreeDanceEligibility(unittest.TestCase):
    def test_empty_hands_offer_only_learned_original_dances(self):
        from server.entertainment_catalog import eligible
        source = prep.catalog()
        self.assertNotIn('object/static/item/item_ribbon.iff', source['items'])
        dances = eligible(['social_entertainer_novice'], '')
        self.assertTrue(dances)
        self.assertTrue(all(row['kind'] == 'dance' for row in dances))
        self.assertEqual(eligible([], ''), [])
        self.assertEqual(eligible(['social_entertainer_novice'], 'object/static/item/item_ribbon.iff'), [])
        self.assertEqual(eligible(['social_entertainer_novice'], 'object/tangible/instrument/mandoviol.iff'), [])


if __name__ == '__main__': unittest.main()
