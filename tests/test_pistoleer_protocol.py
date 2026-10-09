"""Pistoleer request boundaries; combat effects remain native authority."""
import unittest
from unittest.mock import Mock

from server.live_combat import LiveCombatHub


class PistoleerProtocol(unittest.TestCase):
    def setUp(self):
        self.hub = LiveCombatHub()
        self.hub.sessions['pistol'] = {
            'account': 'pistol', 'character_id': '42', 'id': 'session_pistol',
        }
        self.hub._exchange = Mock(return_value={'session_live': True})

    def tearDown(self):
        self.hub.sessions.clear()

    def fields(self, ability, **extra):
        request = dict(character_id='42', session_id='session_pistol', shot_id='pistol-1',
                       item_id='55', ability_id=ability, origin=[0, 1.7, 0], direction=[0, 0, -1])
        request.update(extra)
        return request

    def gesture(self, ability, **extra):
        return self.hub.request('pistol', 'pistoleer', self.fields(ability, **extra))

    def fire(self, ability, **extra):
        fields = dict(target_id='77', two_hands=True, firing_posture='standing')
        fields.update(extra)
        return self.hub.request('pistol', 'fire', self.fields(ability, **fields))

    def payload(self):
        return self.hub._exchange.call_args.args[1]

    def test_gestures_forward_only_pose_and_owned_weapon(self):
        for ability in ('fan_shot', 'run_and_gun'):
            with self.subTest(ability=ability):
                self.gesture(ability, target_ids=['77', '78'], max_targets=999, cone_degrees=360,
                             duration_seconds=999, damage=9999, action_cost=0, cooldown_seconds=0,
                             active=True, learned=True, special_cost_multiplier=0,
                             ordinary_fire_rate_multiplier=999, two_hands=True)
                q = self.payload()
                self.assertEqual(q['action'], 'pistoleer')
                self.assertEqual(q['ability_id'], ability)
                self.assertEqual(q['item_id'], '55')
                self.assertEqual(q['origin'], [0, 1.7, 0])
                self.assertEqual(q['direction'], [0, 0, -1])
                for key in ('target_ids', 'max_targets', 'cone_degrees', 'duration_seconds',
                            'damage', 'action_cost', 'cooldown_seconds', 'active', 'learned',
                            'special_cost_multiplier', 'ordinary_fire_rate_multiplier', 'two_hands'):
                    self.assertNotIn(key, q)

    def test_gesture_rejects_client_bound_target_even_if_empty(self):
        for ability in ('fan_shot', 'run_and_gun'):
            for target in ('77', '', None):
                with self.subTest(ability=ability, target=target), self.assertRaises(ValueError):
                    self.gesture(ability, target_id=target)
        self.hub._exchange.assert_not_called()

    def test_gestures_require_complete_request(self):
        for key in ('shot_id', 'item_id', 'ability_id', 'origin', 'direction'):
            q = self.fields('fan_shot')
            q.pop(key)
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.hub.request('pistol', 'pistoleer', q)
        self.hub._exchange.assert_not_called()

    def test_unknown_gestures_and_cross_route_abilities_rejected(self):
        for ability in ('double_tap', 'disarming_shot', 'showdown', 'fanShot', 'admin', None, 1):
            with self.subTest(ability=ability), self.assertRaises(ValueError):
                self.gesture(ability)
        for ability in ('fan_shot', 'run_and_gun', 'doubleTap', 'disarmingShot2'):
            with self.subTest(ability=ability), self.assertRaises(ValueError):
                self.fire(ability)
        self.hub._exchange.assert_not_called()

    def test_gestures_validate_owner_ids_and_finite_pose(self):
        invalid = ({'character_id': '43'}, {'session_id': 'other'}, {'item_id': 55},
                   {'item_id': '18446744073709551616'}, {'item_id': 'x'},
                   {'shot_id': ''}, {'shot_id': 'short'}, {'shot_id': 'has spaces'},
                   {'shot_id': 's' * 81}, {'shot_id': 1},
                   {'origin': [0, float('nan'), 0]}, {'origin': [0, True, 0]},
                   {'direction': [0, 0]}, {'direction': [0, float('inf'), 0]})
        for changes in invalid:
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                self.gesture('fan_shot', **changes)
        self.hub._exchange.assert_not_called()

    def test_targeted_attacks_have_no_client_damage_authority(self):
        for ability in ('double_tap', 'disarming_shot'):
            self.fire(ability, damage=999, resolved_hits=99, suppression=.99,
                      hit_count=999, duration=999, action_cost=0, cooldown_seconds=0)
            q = self.payload()
            self.assertEqual(q['ability_id'], ability)
            self.assertEqual(q['target_id'], '77')
            self.assertTrue(q['two_hands'])
            self.assertEqual(q['firing_posture'], 'standing')
            for key in ('damage', 'resolved_hits', 'suppression', 'hit_count', 'duration',
                        'action_cost', 'cooldown_seconds'):
                self.assertNotIn(key, q)

    def test_pistoleer_ranged_abilities_require_target(self):
        for ability in ('double_tap', 'disarming_shot', 'showdown'):
            for target in ('', None, 'not-id', '18446744073709551616'):
                with self.subTest(ability=ability, target=target), self.assertRaises(ValueError):
                    self.fire(ability, target_id=target, **(
                        {'volley_id': 'pistol-1', 'volley_index': 0} if ability == 'showdown' else {}))
            q = self.fields(ability)
            with self.subTest(ability=ability, target='missing'), self.assertRaises(ValueError):
                self.hub.request('pistol', 'fire', q)
        self.hub._exchange.assert_not_called()

    def test_showdown_forwards_three_distinct_launches_not_client_effects(self):
        for index in range(3):
            self.fire('showdown', shot_id=f'pistol-{index + 1}', volley_id='pistol-1',
                      volley_index=index, first_landed=True, suppression_applied=False,
                      damage=999, cooldown_paid=True, action_cost=0)
            q = self.payload()
            self.assertEqual(q['volley_id'], 'pistol-1')
            self.assertEqual(q['volley_index'], index)
            self.assertEqual(q['shot_id'], f'pistol-{index + 1}')
            self.assertEqual(q['target_id'], '77')
            for key in ('first_landed', 'suppression_applied', 'damage', 'cooldown_paid', 'action_cost'):
                self.assertNotIn(key, q)
        self.assertEqual(self.hub._exchange.call_count, 3)

    def test_showdown_rejects_malformed_or_missing_volley_metadata(self):
        invalid = ({}, {'volley_id': 'pistol-1'}, {'volley_index': 0},
                   {'volley_id': '', 'volley_index': 0},
                   {'volley_id': 'short', 'volley_index': 1},
                   {'volley_id': 'has spaces', 'volley_index': 1},
                   {'volley_id': 'pistol-1\n', 'volley_index': 1},
                   {'volley_id': 'x' * 81, 'volley_index': 1},
                   {'volley_id': 123, 'volley_index': 1},
                   {'volley_id': 'other-shot', 'volley_index': 0},
                   {'volley_id': 'pistol-1', 'volley_index': -1},
                   {'volley_id': 'pistol-1', 'volley_index': 3},
                   {'volley_id': 'pistol-1', 'volley_index': True},
                   {'volley_id': 'pistol-1', 'volley_index': 1.0},
                   {'volley_id': 'pistol-1', 'volley_index': '1'},
                   {'volley_id': 'pistol-1', 'volley_index': 1, 'shot_id': ''},
                   {'volley_id': 'pistol-1', 'volley_index': 1, 'shot_id': 'short'},
                   {'volley_id': 'pistol-1', 'volley_index': 1, 'shot_id': 'has spaces'})
        for changes in invalid:
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                self.fire('showdown', **changes)
        self.hub._exchange.assert_not_called()

    def test_non_showdown_requests_reject_volley_metadata(self):
        for extra in ({'volley_id': 'pistol-1'}, {'volley_index': 0}):
            for ability in ('double_tap', 'disarming_shot', 'bleeding_shot', 'last_ditch'):
                with self.subTest(ability=ability, extra=extra), self.assertRaises(ValueError):
                    self.fire(ability, **extra)
            for ability in ('fan_shot', 'run_and_gun'):
                with self.subTest(ability=ability, extra=extra), self.assertRaises(ValueError):
                    self.gesture(ability, **extra)
            q = self.fields('double_tap', **extra)
            q.pop('ability_id')
            with self.assertRaises(ValueError):
                self.hub.request('pistol', 'fire', q)
        self.hub._exchange.assert_not_called()


if __name__ == '__main__':
    unittest.main()
