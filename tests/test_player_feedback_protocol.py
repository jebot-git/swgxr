import unittest
from unittest.mock import patch

from server.datapad_protocol import datapad
from server.profession_protocol import player_context
from server.profession_catalog import catalog
from tools.server.combat_protocol_smoke import fixture, numbers, pack, ascii_string


class PlayerFeedbackProtocolTests(unittest.TestCase):
    def test_readout_preserves_distinct_current_maximum_wounds_and_posture(self):
        record = fixture(posture=12)[0]
        context = player_context({'variables': {'replication': {'objects': {'o123': record}}}}, '123')
        self.assertTrue(context['complete'])
        self.assertEqual([context['ham'][i] for i in (0, 3, 6)], [800, 600, 400])
        self.assertEqual([context['max_ham'][i] for i in (0, 3, 6)], [1000, 900, 800])
        self.assertEqual([context['wounds'][i] for i in (0, 3, 6)], [20, 30, 40])
        self.assertEqual(context['posture'], 12)
        self.assertEqual(context['combat_authority'], 'local_prediction_only')

    def test_unknown_pools_do_not_invent_health(self):
        record = fixture()[0]
        record.pop('baseline6')
        context = player_context({'variables': {'replication': {'objects': {'o123': record}}}}, '123')
        self.assertFalse(context['complete'])
        for field in ('ham', 'max_ham'):
            self.assertEqual(context[field], [])
        self.assertEqual(context['wounds'][0], 20)

    def test_datapad_skills_are_owner_replication_not_starting_profession(self):
        objects = {
            'o123': {'type': 0x4352454f},
            'o2': {'parentId': '123', 'templateCrc': 17},
            'o3': {'parentId': '123', 'type': 0x504c4159,
                   'baseline8': (numbers([]) + numbers([])).hex(),
                   'baseline9': (numbers([]) + bytes(16) + numbers([])).hex()},
        }
        learned = ['combat_marksman_novice', 'combat_marksman_pistol_01']
        raw = bytes(8) + numbers([1000]*9) + pack('II', len(learned), 1)
        objects['o123']['baseline1'] = (raw + b''.join(ascii_string(s) for s in learned)).hex()
        result = {'variables': {'replication': {'objects': objects}}}
        with patch('server.datapad_protocol.template_names', return_value={17: 'object/tangible/datapad/shared_character_datapad.iff'}):
            readout = datapad(result, '123')
            self.assertEqual(readout['skills'], learned)
            self.assertTrue(readout['skills_complete'])
            objects['o123'].pop('baseline1')
            unknown = datapad(result, '123')
            self.assertFalse(unknown['skills_complete'])
            self.assertEqual(unknown['skills'], [])

    def test_original_graph_retains_recursive_tiers_and_master_prerequisites(self):
        data = catalog()
        marksman = next(p for p in data['professions'] if p['id'] == 'combat_marksman')
        nodes = {n['id']: n for n in marksman['nodes']}
        self.assertEqual(len(nodes), 18)
        self.assertIn('combat_marksman_pistol_03', nodes['combat_marksman_pistol_04']['requires'])
        self.assertIn('combat_marksman_rifle_04', nodes['combat_marksman_master']['requires'])
        self.assertGreater(nodes['combat_marksman_pistol_02']['xp_cost'], 0)
        self.assertTrue(data['read_only'])
        self.assertEqual(len(data['provenance']), 3)

    def test_malformed_original_modifier_is_recorded_not_guessed(self):
        data = catalog()
        warning = next(w for w in data['warnings'] if w['skill'] == 'combat_commando_heavyweapon_speed_01')
        self.assertEqual(warning['field'], 'SKILL_MODS')
        self.assertIn('20heavy_', warning['raw'])


if __name__ == '__main__':
    unittest.main()
