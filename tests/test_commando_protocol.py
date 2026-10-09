"""Commando input admits intent; native equipment and receipts own the outcome."""
import unittest
from unittest.mock import Mock

from server.live_combat import LiveCombatHub
from server.profession_protocol import translate
from server.scout_protocol import command


class CommandoProtocolTests(unittest.TestCase):
    def setUp(self):
        self.hub = LiveCombatHub()
        self.hub.sessions['commando'] = {
            'account': 'commando', 'character_id': '42', 'id': 'session_commando'}
        self.hub._exchange = Mock(return_value={'session_live': True})

    def tearDown(self):
        self.hub.sessions.clear()

    def request(self, ability='', action='commando', **extra):
        data = dict(character_id='42', session_id='session_commando', item_id='55',
                    shot_id='commando-123', ability_id=ability, origin=[0, 1.7, 0],
                    direction=[0, 0, -1], two_hands=True)
        data.update(extra)
        self.hub.request('commando', action, data)
        return self.hub._exchange.call_args.args[1]

    def test_native_area_selection_and_self_ultimate(self):
        for ability in ('', 'overdrive'):
            payload = self.request(ability, damage=10000, charges=10000,
                                   duration_seconds=10000, target_ids=['77'])
            self.assertEqual(payload['ability_id'], ability)
            for forbidden in ('damage', 'charges', 'duration_seconds', 'target_ids'):
                self.assertNotIn(forbidden, payload)
            with self.assertRaises(ValueError):
                self.request(ability, target_id='77')

    def test_equipment_specific_regular_modes_and_rocket_registration(self):
        for ability in ('focused_discharge', 'acid_spray'):
            self.assertEqual(self.request(ability, target_id='77')['target_id'], '77')
            with self.assertRaises(ValueError):
                self.request(ability)
        self.assertEqual(self.request('focused_discharge', action='fire', target_id='77')['ability_id'],
                         'focused_discharge')
        for ability in ('acid_spray', 'overdrive'):
            with self.assertRaises(ValueError):
                self.request(ability, action='fire', target_id='77')

    def test_strict_pose_identity_and_route_boundaries(self):
        for fields in ({'two_hands': 1}, {'shot_id': 'bad\n'}, {'shot_id': 'short'},
                       {'origin': [0, float('nan'), 0]}, {'direction': [False, 0, 1]},
                       {'item_id': '18446744073709551616'}, {'character_id': '43'},
                       {'volley_id': 'commando-123'}):
            with self.subTest(fields=fields), self.assertRaises(ValueError):
                self.request(**fields)
        for ability in ('fan_shot', 'rifleman_focus', 'full_auto_sweep', None, 1):
            with self.subTest(ability=ability), self.assertRaises(ValueError):
                self.request(ability)
        self.assertIs(self.request(two_hands=False)['two_hands'], False)

    def test_template_folder_does_not_leak_combined_profession_bonuses(self):
        for template in ('rifle/rifle_flame_thrower', 'rifle/rifle_acid_beam',
                         'pistol/pistol_launcher', 'heavy/heavy_rocket_launcher'):
            profile = translate({'template': 'object/weapon/ranged/'+template+'.iff',
                                 'native_family': 'commando'},
                                {'rifle_speed': 100, 'pistol_speed': 100, 'heavy_speed': 100},
                                ['combat_marksman_master', 'combat_rifleman_master',
                                 'combat_pistol_master', 'combat_commando_master'])
            self.assertEqual(profile['profession']['weapon_class'], 'heavy')
            self.assertEqual(profile['profession']['rpm_scale'], 1)
            self.assertEqual(profile['abilities'], [])

    def test_grenade_is_owned_throw_intent_without_damage_or_landing_claim(self):
        data = dict(position=[1, 2, 3], request_id='grenade_123', item_id='55', target_id='77',
                    building_id='123', cell_index=2, charges=999, damage=999,
                    landing_position=[8000, 0, 0], fuse_seconds=0)
        payload = command('grenade', data)
        self.assertEqual(payload['target_id'], '77')
        self.assertEqual(payload['building_id'], '123')
        for forbidden in ('charges', 'damage', 'landing_position', 'fuse_seconds'):
            self.assertNotIn(forbidden, payload)
        for fields in ({'request_id': ''}, {'target_id': '0'}, {'item_id': 55},
                       {'cell_index': True}, {'building_id': '0'}, {'position': [9000, 0, 0]}):
            with self.subTest(fields=fields), self.assertRaises(ValueError):
                command('grenade', dict(data, **fields))


if __name__ == '__main__':
    unittest.main()
