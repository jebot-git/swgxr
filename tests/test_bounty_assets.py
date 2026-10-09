"""Bounty appearance coverage and exact original-media provenance."""
import hashlib
import io
import json
from pathlib import Path
import re
import sys
import unittest
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools/assets'))
from swg_formats import TreSet
from prepare_bounty_assets import required_failures


class BountyAssetReadiness(unittest.TestCase):
    def test_partial_wardrobe_does_not_hide_missing_body_or_conversion_error(self):
        missing = {'phase': 'npc', 'template': 'original_target',
                   'errors': [{'phase': 'wearable', 'resource': 'appearance/missing_original.lmg'}]}
        self.assertEqual(required_failures([missing], {'original_target': {'functional_ready': True}}, set()), [])
        self.assertEqual(required_failures([missing], {'original_target': {'functional_ready': False}}, set()), [missing])
        # An existing source that failed conversion is not a missing-media exception.
        self.assertEqual(required_failures([missing], {'original_target': {'functional_ready': True}},
                                          {'appearance/missing_original.lmg'}), [missing])

    def test_missing_droid_items_effects_catalogs_or_unknown_errors_are_fatal(self):
        failures = [{'phase': phase, 'error': 'required dependency unavailable'}
                    for phase in ('inventory', 'delivery_effect', 'terminal_catalog', 'unknown')]
        self.assertEqual(required_failures(failures, {}, set()), failures)


@unittest.skipUnless((ROOT/'runtime/assets/bounty/coverage.json').is_file(),
                     'Prepared supplied bounty assets required')
class BountyAssets(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = ROOT/'runtime/assets/bounty'
        cls.coverage = json.loads((cls.directory/'coverage.json').read_text())
        cls.effects = json.loads((cls.directory/'assets.json').read_text())
        cls.ambient = ROOT/'runtime/assets/ambient_npcs'
        cls.catalog = json.loads((cls.ambient/'catalog.json').read_text())
        cls.media = TreSet(ROOT/'runtime/asset_sources/active_tre')

    def test_all_authored_target_levels_dressgroups_and_informants_are_covered(self):
        manager = ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/managers/mission/mission_manager.lua'
        targets = set(re.findall(r'"(bh_[a-z0-9_]+)"', manager.read_text()))
        self.assertEqual(set().union(*map(set, self.coverage['target_levels'].values())), targets)
        self.assertEqual(len(targets), 34)
        self.assertEqual(set(self.coverage['target_zones']),
                         {'corellia','dantooine','dathomir','endor','lok','naboo','rori','talus','tatooine','yavin4'})
        templates = set()
        for name, row in self.coverage['mobiles'].items():
            self.assertTrue(row['templates'], name)
            source = (ROOT/row['source']).read_text()
            expected = set(re.findall(r'"(object/(?:mobile|creature)/[a-z0-9_/]+\.iff)"', source))
            for group in row['dressgroups']:
                self.assertIn('"'+group['source_reference']+'"', source)
                expected.update(re.findall(r'"(object/(?:mobile|creature)/[a-z0-9_/]+\.iff)"',
                                           (ROOT/group['source']).read_text()))
            self.assertEqual(set(row['templates']), expected, name)
            templates.update(expected)
        self.assertEqual(set(self.coverage['npc_templates']), templates)
        self.assertEqual(len(templates), 75)
        self.assertEqual(self.coverage['mobiles']['informant_npc']['templates'],
                         ['object/mobile/dressed_hutt_informant_quest.iff'])

    def test_every_target_has_actual_original_body_and_native_dead_pose(self):
        self.assertTrue(self.coverage['functional_ready'])
        self.assertEqual(self.coverage['blocking_failures'], [])
        bodies = {}
        for template, row in self.coverage['npc_templates'].items():
            descriptor = self.catalog['races'][template]
            self.assertTrue(row['functional_ready'], template)
            self.assertEqual(row['body'], descriptor['body'])
            if row['body'] not in bodies:
                bodies[row['body']] = json.loads((self.ambient/row['body']).read_text())
            body = bodies[row['body']]
            self.assertEqual(body['appearance'], row['appearance'])
            self.assertTrue(body['bones'])
            self.assertTrue(any(part['mesh']['surfaces'] for part in body['parts']))
            self.assertIn('idle', body['animations'])
            self.assertIn('walk', body['animations'])
            self.assertTrue(descriptor['incapacitated_pose']['ready'], template)
            pose = body['animation_library']['incapacitated']
            self.assertIn(pose['source'], self.media.entries)
            self.assertTrue((self.ambient/pose['path']).is_file())
            for outfit in descriptor['default_outfit']:
                self.assertTrue((self.ambient/outfit['model']).is_file())

    def test_droid_items_are_original_models_and_mobile_appearances_are_exact(self):
        inventory = ROOT/'runtime/assets/inventory'
        expected = {'object/tangible/mission/mission_bounty_droid_probot.iff': 'appearance/eqp_tool_homing_beacon.apt',
                    'object/tangible/mission/mission_bounty_droid_seeker.iff': 'appearance/maul_probe_droid.sat'}
        self.assertEqual(set(self.coverage['inventory_items']), set(expected))
        for template, appearance in expected.items():
            row = self.coverage['inventory_items'][template]
            self.assertTrue(row['ready'])
            raw = (inventory/row['model']).read_bytes()
            self.assertEqual(hashlib.sha256(raw).hexdigest(), row['model_sha256'])
            model = json.loads(raw)
            self.assertEqual(model['source_appearance'], appearance)
            self.assertTrue(model['surfaces'])
        self.assertEqual(self.coverage['mobiles']['probot']['templates'], ['object/mobile/probot.iff'])
        self.assertEqual(self.coverage['mobiles']['seeker']['templates'],
                         ['object/creature/npc/droid/crafted/probe_droid.iff'])

    def test_source_failures_are_missing_media_not_hidden_or_replaced(self):
        for path, expected in self.coverage['files_sha256'].items():
            self.assertEqual(hashlib.sha256((ROOT/path).read_bytes()).hexdigest(), expected, path)
        for path, source in self.coverage['source_hashes'].items():
            self.assertEqual(hashlib.sha256(self.media.read(path)).hexdigest(), source['sha256'], path)
        unresolved = {template for template, row in self.coverage['npc_templates'].items() if not row['ready']}
        self.assertEqual(unresolved, {row['template'] for row in self.coverage['failures']})
        self.assertEqual(self.coverage['passed'], not self.coverage['failures'])
        for failure in self.coverage['failures']:
            self.assertEqual(failure['phase'], 'npc')
            descriptor = self.catalog['races'][failure['template']]
            self.assertFalse(descriptor['appearance_complete'])
            self.assertTrue(failure['errors'])
            for error in failure['errors']:
                self.assertEqual(error['phase'], 'wearable')
                self.assertNotIn(error['resource'], self.media.entries)
                self.assertIn(error, descriptor['appearance_failures'])

    def test_terminal_anchors_are_exact_existing_source_placements(self):
        self.assertEqual(sum(map(len, self.coverage['terminals'].values())), 34)
        for planet, rows in self.coverage['terminals'].items():
            source = ROOT/('runtime/assets/services/catalog.json' if planet == 'tatooine' else
                          'runtime/assets/planets/'+planet+'/services/catalog.json')
            expected = [row for row in json.loads(source.read_text())['static_terminals']
                        if row['template'] == 'object/tangible/terminal/terminal_mission_bounty.iff']
            self.assertEqual(rows, expected)
            self.assertEqual(len({row['id'] for row in rows}), len(rows))
            self.assertTrue(all(row['id_kind'] == 'snapshot_object' for row in rows))

    def test_delivery_effect_uses_original_textures_audio_and_hashed_sources(self):
        self.assertEqual(self.effects['bounty_effects'], {'probot_delivery': 'clienteffect/probot_delivery.cef'})
        self.assertEqual(self.effects['failures'], [])
        for path, row in self.effects['provenance'].items():
            self.assertEqual(hashlib.sha256(self.media.read(path)).hexdigest(), row['sha256'], path)
        effect = self.effects['effects']['clienteffect/probot_delivery.cef']
        self.assertTrue(effect['omitted_camera_shake_for_xr'])
        self.assertEqual(effect['sounds'], ['sound/probot_impact.snd'])
        for sound in effect['sounds']:
            self.assertTrue(all((self.directory/path).is_file() for path in self.effects['sounds'][sound]['samples']))
        for particle in self.effects['particles'].values():
            self.assertTrue(particle['emitters'])
            for emitter in particle['emitters']:
                material = emitter['material']
                original = Image.open(io.BytesIO(self.media.read(material['texture_source']))).convert('RGBA')
                converted = Image.open(self.directory/material['texture']).convert('RGBA')
                self.assertEqual((original.size, original.tobytes()), (converted.size, converted.tobytes()))


if __name__ == '__main__':
    unittest.main()
