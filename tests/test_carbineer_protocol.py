"""Carbineer wire boundaries: owned intent only; native combat authority."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock

from server.live_combat import LiveCombatHub


class CarbineerProtocol(unittest.TestCase):
    AREA = ('full_auto_sweep', 'tactical_brace', 'charge_blast')
    TARGETED = ('crippling_shot', 'wild_shot', 'charge_shot')

    def setUp(self):
        self.hub = LiveCombatHub()
        self.hub.sessions['carbine'] = {
            'account': 'carbine', 'character_id': '42', 'id': 'session_carbine',
        }
        self.hub._exchange = Mock(return_value={'session_live': True})

    def tearDown(self):
        self.hub.sessions.clear()

    def fields(self, ability, **extra):
        request = dict(character_id='42', session_id='session_carbine', shot_id='carbine-1',
                       item_id='55', ability_id=ability, origin=[0, 1.7, 0],
                       direction=[0, 0, -1], two_hands=True)
        request.update(extra)
        return request

    def area(self, ability, **extra):
        return self.hub.request('carbine', 'carbineer', self.fields(ability, **extra))

    def fire(self, ability, **extra):
        fields = dict(target_id='77', firing_posture='standing')
        fields.update(extra)
        return self.hub.request('carbine', 'fire', self.fields(ability, **fields))

    def payload(self):
        return self.hub._exchange.call_args.args[1]

    def test_area_and_buff_forward_only_pose_and_owned_weapon(self):
        for ability in self.AREA:
            with self.subTest(ability=ability):
                self.area(ability, target_ids=['77', '78'], max_targets=999, cone_degrees=360,
                          duration_seconds=999, damage=9999, action_cost=0, cooldown_seconds=0,
                          active=True, learned=True, control_chance_bonus=999, ammo_cost=0,
                          range=999, firing_posture='prone')
                q = self.payload()
                self.assertEqual(q['action'], 'carbineer')
                self.assertEqual(q['ability_id'], ability)
                self.assertEqual(q['item_id'], '55')
                self.assertEqual(q['origin'], [0, 1.7, 0])
                self.assertEqual(q['direction'], [0, 0, -1])
                self.assertIs(q['two_hands'], True)
                for key in ('target_ids', 'max_targets', 'cone_degrees', 'duration_seconds',
                            'damage', 'action_cost', 'cooldown_seconds', 'active', 'learned',
                            'control_chance_bonus', 'ammo_cost', 'range', 'firing_posture'):
                    self.assertNotIn(key, q)

    def test_area_rejects_bound_targets_even_if_empty(self):
        for ability in self.AREA:
            for target in ('77', '', None):
                with self.subTest(ability=ability, target=target), self.assertRaises(ValueError):
                    self.area(ability, target_id=target)
        self.hub._exchange.assert_not_called()

    def test_area_requires_complete_request_and_literal_two_hands(self):
        for key in ('shot_id', 'item_id', 'ability_id', 'origin', 'direction', 'two_hands'):
            q = self.fields('full_auto_sweep')
            q.pop(key)
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.hub.request('carbine', 'carbineer', q)
        for ability in self.AREA:
            for value in (False, None, 1, 0, 'true', []):
                with self.subTest(ability=ability, value=value), self.assertRaises(ValueError):
                    self.area(ability, two_hands=value)
        self.hub._exchange.assert_not_called()

    def test_unknown_and_cross_route_abilities_rejected(self):
        for ability in self.TARGETED + ('suppression_fire', 'forward_check', 'fullAutoArea2', None, 1):
            with self.subTest(ability=ability), self.assertRaises(ValueError):
                self.area(ability)
        for ability in self.AREA + ('forward_check', 'chargeShot2', 'wildShot1'):
            with self.subTest(ability=ability), self.assertRaises(ValueError):
                self.fire(ability)
        for action in ('pistoleer', 'pikeman', 'fencer', 'swordsman', 'tka'):
            for ability in self.AREA:
                with self.subTest(action=action, ability=ability), self.assertRaises(ValueError):
                    self.hub.request('carbine', action, self.fields(ability))
        self.hub._exchange.assert_not_called()

    def test_area_validates_owner_ids_and_finite_pose(self):
        invalid = ({'character_id': '43'}, {'session_id': 'other'}, {'item_id': 55},
                   {'item_id': '18446744073709551616'}, {'item_id': 'x'},
                   {'shot_id': ''}, {'shot_id': 'short'}, {'shot_id': 'has spaces'},
                   {'shot_id': 'carbine-1\n'}, {'shot_id': 'cárbine-1'},
                   {'shot_id': 's' * 81}, {'shot_id': 1},
                   {'origin': [0, float('nan'), 0]}, {'origin': [0, True, 0]},
                   {'direction': [0, 0]}, {'direction': [0, float('inf'), 0]})
        for changes in invalid:
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                self.area('full_auto_sweep', **changes)
        self.hub._exchange.assert_not_called()

    def test_token_limits_match_native_ascii_format(self):
        for token in ('A_123-45', 'a' * 80):
            self.area('tactical_brace', shot_id=token)
            self.assertEqual(self.payload()['shot_id'], token)
        self.assertEqual(self.hub._exchange.call_count, 2)

    def test_targeted_attacks_preserve_contact_without_client_effect_authority(self):
        for ability in self.TARGETED + ('suppression_fire',):
            self.fire(ability, damage=999, effect_chance=999, knockdown=True,
                      slow_multiplier=0, duration=999, action_cost=0, cooldown_seconds=0)
            q = self.payload()
            self.assertEqual(q['ability_id'], ability)
            self.assertEqual(q['target_id'], '77')
            self.assertTrue(q['two_hands'])
            self.assertEqual(q['firing_posture'], 'standing')
            for key in ('damage', 'effect_chance', 'knockdown', 'slow_multiplier',
                        'duration', 'action_cost', 'cooldown_seconds'):
                self.assertNotIn(key, q)

    def test_targeted_attacks_require_native_object_target(self):
        for ability in self.TARGETED:
            for target in ('', None, 77, 'not-id', '18446744073709551616'):
                with self.subTest(ability=ability, target=target), self.assertRaises(ValueError):
                    self.fire(ability, target_id=target)
            q = self.fields(ability)
            with self.subTest(ability=ability, target='missing'), self.assertRaises(ValueError):
                self.hub.request('carbine', 'fire', q)
        self.hub._exchange.assert_not_called()

    def test_carbineer_rejects_showdown_volley_metadata(self):
        for extra in ({'volley_id': 'carbine-1'}, {'volley_index': 0}):
            for ability in self.TARGETED:
                with self.subTest(ability=ability, extra=extra), self.assertRaises(ValueError):
                    self.fire(ability, **extra)
            for ability in self.AREA:
                with self.subTest(ability=ability, extra=extra), self.assertRaises(ValueError):
                    self.area(ability, **extra)
        self.hub._exchange.assert_not_called()

    def test_movement_revision_is_bounded_integer_context(self):
        self.area('charge_blast', movement_revision=2**53-1)
        self.assertEqual(self.payload()['movement_revision'], 2**53-1)
        self.hub._exchange.reset_mock()
        for value in (True, -1, 2**53, 1.5, '1'):
            with self.subTest(value=value), self.assertRaises(ValueError):
                self.area('charge_blast', movement_revision=value)
        self.hub._exchange.assert_not_called()

    def test_new_gesture_actions_keep_bounded_native_diagnostics(self):
        with tempfile.TemporaryDirectory() as directory:
            active = {'folder': Path(directory)}
            for action in ('carbineer', 'pistoleer'):
                self.hub._record(active, {'action': action, 'shot_id': 'carbine-1',
                                        'item_id': '55', 'password': 'not-for-audit'},
                                 {'mutation': {'success': True, 'damage': 12},
                                  'snapshot': {'player': {'ham': [100, 100, 100]},
                                               'actors': [{'private': 'not-for-audit'}]}})
            audit = json.loads((Path(directory) / 'audit.json').read_text())
            self.assertEqual([e['action'] for e in audit['events']], ['carbineer', 'pistoleer'])
            self.assertEqual(audit['counts'], {'carbineer': 1, 'pistoleer': 1})
            self.assertEqual(audit['capacity'], 128)
            self.assertEqual(audit['events'][0]['damage'], 12)
            self.assertNotIn('not-for-audit', json.dumps(audit))


if __name__ == '__main__':
    unittest.main()
