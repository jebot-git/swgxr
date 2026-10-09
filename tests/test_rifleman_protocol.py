"""Rifleman ownership and intent boundaries; native code owns damage and volleys."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock

from server.live_combat import LiveCombatHub


class RiflemanProtocol(unittest.TestCase):
    TARGETED = ('piercing_shot', 'flurry_shot', 'surprise_shot', 'sniper_shot')

    def setUp(self):
        self.hub = LiveCombatHub()
        self.hub.sessions['rifle'] = {
            'account': 'rifle', 'character_id': '42', 'id': 'session_rifle',
        }
        self.hub._exchange = Mock(return_value={'session_live': True})

    def tearDown(self):
        self.hub.sessions.clear()

    def fields(self, ability, **extra):
        request = dict(character_id='42', session_id='session_rifle', shot_id='rifleman-1',
                       item_id='55', ability_id=ability, origin=[0, 1.7, 0],
                       direction=[0, 0, -1], two_hands=True)
        request.update(extra)
        return request

    def focus(self, **extra):
        return self.hub.request('rifle', 'rifleman', self.fields('rifleman_focus', **extra))

    def fire(self, ability, **extra):
        fields = dict(target_id='77', firing_posture='standing')
        if ability == 'flurry_shot':
            fields.update(volley_id='rifleman-1', volley_index=0)
        fields.update(extra)
        return self.hub.request('rifle', 'fire', self.fields(ability, **fields))

    def payload(self):
        return self.hub._exchange.call_args.args[1]

    def test_focus_forwards_only_owned_intent_not_buff_claims(self):
        self.focus(target_ids=['77'], damage_multiplier=999, active=True, learned=True,
                   duration_seconds=999, action_cost=0, cooldown_seconds=0,
                   ammunition=999, ultimate_selected=True, firing_posture='prone')
        q = self.payload()
        self.assertEqual(q['action'], 'rifleman')
        self.assertEqual(q['ability_id'], 'rifleman_focus')
        self.assertEqual(q['item_id'], '55')
        self.assertEqual(q['origin'], [0, 1.7, 0])
        self.assertEqual(q['direction'], [0, 0, -1])
        self.assertIs(q['two_hands'], True)
        for key in ('target_ids', 'damage_multiplier', 'active', 'learned',
                    'duration_seconds', 'action_cost', 'cooldown_seconds',
                    'ammunition', 'ultimate_selected', 'firing_posture'):
            self.assertNotIn(key, q)

    def test_focus_rejects_targets_and_volley_metadata_even_empty(self):
        for extra in ({'target_id': ''}, {'target_id': None}, {'target_id': '77'},
                      {'volley_id': ''}, {'volley_index': 0}):
            with self.subTest(extra=extra), self.assertRaises(ValueError):
                self.focus(**extra)
        self.hub._exchange.assert_not_called()

    def test_focus_requires_complete_pose_and_supported_finish(self):
        for key in ('shot_id', 'item_id', 'ability_id', 'origin', 'direction', 'two_hands'):
            q = self.fields('rifleman_focus')
            q.pop(key)
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.hub.request('rifle', 'rifleman', q)
        for value in (False, None, 1, 0, 'true', []):
            with self.subTest(value=value), self.assertRaises(ValueError):
                self.focus(two_hands=value)
        self.hub._exchange.assert_not_called()

    def test_focus_validates_owner_ids_tokens_and_finite_pose(self):
        invalid = ({'character_id': '43'}, {'session_id': 'other'}, {'item_id': 55},
                   {'item_id': '18446744073709551616'}, {'item_id': 'x'},
                   {'shot_id': ''}, {'shot_id': 'short'}, {'shot_id': 'has spaces'},
                   {'shot_id': 'rifleman-1\n'}, {'shot_id': 'r\u00edfleman-1'},
                   {'shot_id': 's' * 81}, {'shot_id': 1},
                   {'origin': [0, float('nan'), 0]}, {'origin': [0, True, 0]},
                   {'direction': [0, 0]}, {'direction': [0, float('inf'), 0]})
        for extra in invalid:
            with self.subTest(extra=extra), self.assertRaises(ValueError):
                self.focus(**extra)
        self.hub._exchange.assert_not_called()

    def test_focus_token_boundaries_and_bounded_movement_context(self):
        for token in ('A_123-45', 'a' * 80):
            self.focus(shot_id=token, movement_revision=2**53 - 1)
            self.assertEqual(self.payload()['shot_id'], token)
            self.assertEqual(self.payload()['movement_revision'], 2**53 - 1)
        self.hub._exchange.reset_mock()
        for revision in (True, -1, 2**53, 1.5, '1'):
            with self.subTest(revision=revision), self.assertRaises(ValueError):
                self.focus(movement_revision=revision)
        self.hub._exchange.assert_not_called()

    def test_unknown_and_cross_route_abilities_rejected(self):
        for ability in self.TARGETED + ('lethal_shot', 'riflemanFocus', 'tactical_brace', None, 1):
            with self.subTest(ability=ability), self.assertRaises(ValueError):
                self.hub.request('rifle', 'rifleman', self.fields(ability))
        for ability in ('rifleman_focus', 'head_shot', 'headShot2', 'mindShot2', 'sniperShot'):
            with self.subTest(ability=ability), self.assertRaises(ValueError):
                self.fire(ability)
        for action in ('pistoleer', 'carbineer', 'pikeman', 'fencer', 'swordsman', 'tka'):
            with self.subTest(action=action), self.assertRaises(ValueError):
                self.hub.request('rifle', action, self.fields('rifleman_focus'))
        self.hub._exchange.assert_not_called()

    def test_targeted_attacks_preserve_contact_without_client_damage_authority(self):
        for ability in self.TARGETED + ('lethal_shot',):
            self.fire(ability, damage=999, armour_multiplier=0, effective_health_fraction=1,
                      damage_multiplier=999, focus_active=True, hit_count=99, action_cost=0,
                      cooldown_seconds=0, master=True)
            q = self.payload()
            self.assertEqual(q['ability_id'], ability)
            self.assertEqual(q['target_id'], '77')
            self.assertTrue(q['two_hands'])
            self.assertEqual(q['firing_posture'], 'standing')
            for key in ('damage', 'armour_multiplier', 'effective_health_fraction',
                        'damage_multiplier', 'focus_active', 'hit_count', 'action_cost',
                        'cooldown_seconds', 'master'):
                self.assertNotIn(key, q)

    def test_rifle_attacks_require_native_object_target(self):
        for ability in self.TARGETED:
            for target in ('', None, 77, 'not-id', '18446744073709551616'):
                with self.subTest(ability=ability, target=target), self.assertRaises(ValueError):
                    self.fire(ability, target_id=target)
            q = self.fields(ability)
            with self.subTest(ability=ability, target='missing'), self.assertRaises(ValueError):
                self.hub.request('rifle', 'fire', q)
        self.hub._exchange.assert_not_called()

    def test_sniper_requires_explicit_supported_grip(self):
        for value in (False, None, 1, 0, 'true'):
            with self.subTest(value=value), self.assertRaises(ValueError):
                self.fire('sniper_shot', two_hands=value)
        q = self.fields('sniper_shot', target_id='77')
        q.pop('two_hands')
        with self.assertRaises(ValueError):
            self.hub.request('rifle', 'fire', q)
        self.hub._exchange.assert_not_called()

    def test_flurry_forwards_three_physical_launches_with_native_owned_costs(self):
        for index in range(3):
            self.fire('flurry_shot', shot_id=f'rifleman-{index + 1}', volley_index=index,
                      cooldown_paid=True, focus_active=True, damage=999,
                      volley_complete=True, suppression_applied=False)
            q = self.payload()
            self.assertEqual(q['volley_id'], 'rifleman-1')
            self.assertEqual(q['volley_index'], index)
            self.assertEqual(q['shot_id'], f'rifleman-{index + 1}')
            self.assertEqual(q['target_id'], '77')
            for key in ('cooldown_paid', 'focus_active', 'damage',
                        'volley_complete', 'suppression_applied'):
                self.assertNotIn(key, q)
        self.assertEqual(self.hub._exchange.call_count, 3)

    def test_flurry_rejects_malformed_or_missing_volley_metadata(self):
        invalid = ({}, {'volley_id': 'rifleman-1'}, {'volley_index': 0},
                   {'volley_id': '', 'volley_index': 0},
                   {'volley_id': 'short', 'volley_index': 1},
                   {'volley_id': 'has spaces', 'volley_index': 1},
                   {'volley_id': 'rifleman-1\n', 'volley_index': 1},
                   {'volley_id': 'r\u00edfleman-1', 'volley_index': 1},
                   {'volley_id': 'x' * 81, 'volley_index': 1},
                   {'volley_id': 123, 'volley_index': 1},
                   {'volley_id': 'other-shot', 'volley_index': 0},
                   {'volley_id': 'rifleman-1', 'volley_index': -1},
                   {'volley_id': 'rifleman-1', 'volley_index': 3},
                   {'volley_id': 'rifleman-1', 'volley_index': True},
                   {'volley_id': 'rifleman-1', 'volley_index': 1.0},
                   {'volley_id': 'rifleman-1', 'volley_index': '1'},
                   {'volley_id': 'rifleman-1', 'volley_index': 1, 'shot_id': ''},
                   {'volley_id': 'rifleman-1', 'volley_index': 1, 'shot_id': 'short'})
        for extra in invalid:
            q = self.fields('flurry_shot', target_id='77', **extra)
            with self.subTest(extra=extra), self.assertRaises(ValueError):
                self.hub.request('rifle', 'fire', q)
        self.hub._exchange.assert_not_called()

    def test_non_volley_attacks_and_impact_reject_volley_metadata(self):
        for extra in ({'volley_id': 'rifleman-1'}, {'volley_index': 0}):
            for ability in ('lethal_shot', 'piercing_shot', 'surprise_shot', 'sniper_shot'):
                with self.subTest(ability=ability, extra=extra), self.assertRaises(ValueError):
                    self.fire(ability, **extra)
            q = self.fields('flurry_shot', target_id='77', hit_position=[0, 1, -5],
                            projectile_age_seconds=.1, **extra)
            with self.assertRaises(ValueError):
                self.hub.request('rifle', 'impact', q)
        self.hub._exchange.assert_not_called()

    def test_focus_keeps_bounded_native_diagnostics(self):
        with tempfile.TemporaryDirectory() as directory:
            active = {'folder': Path(directory)}
            self.hub._record(active, {'action': 'rifleman', 'shot_id': 'rifleman-1',
                                     'item_id': '55', 'password': 'not-for-audit'},
                             {'mutation': {'success': True},
                              'snapshot': {'player': {'ham': [100, 100, 100]},
                                           'actors': [{'private': 'not-for-audit'}]}})
            audit = json.loads((Path(directory) / 'audit.json').read_text())
            self.assertEqual(audit['counts'], {'rifleman': 1})
            self.assertEqual(audit['capacity'], 128)
            self.assertEqual(audit['events'][0]['action'], 'rifleman')
            self.assertNotIn('not-for-audit', json.dumps(audit))


if __name__ == '__main__':
    unittest.main()
