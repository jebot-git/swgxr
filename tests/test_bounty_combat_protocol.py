"""BH input ownership and bounded physical contact reports, without game authority."""
import unittest
from unittest.mock import Mock

from server.live_combat import LiveCombatHub
from server.bounty_combat_protocol import contact_fields


class BountyCombatProtocol(unittest.TestCase):
    def setUp(self):
        self.hub = LiveCombatHub()
        self.hub.sessions['hunter'] = dict(account='hunter', character_id='42', id='owned')
        self.hub._exchange = Mock(return_value={'session_live': True})

    def tearDown(self):
        self.hub.sessions.clear()

    def request(self, action, ability=None, **extra):
        data = dict(character_id='42', session_id='owned', shot_id='bounty-001',
                    item_id='55', origin=[0, 1.5, 0], direction=[0, 0, -1], two_hands=True)
        if ability is not None:
            data['ability_id'] = ability
        data.update(extra)
        return self.hub.request('hunter', action, data)

    def command(self):
        return self.hub._exchange.call_args.args[1]

    def test_gestures_and_attacks_forward_intent_only(self):
        cases = [('bountyhunter', 'underhand_shot', {}),
                 ('bountyhunter', 'duelist_stance', {'target_id': '77', 'two_hands': False})]
        cases += [('fire', ability, {'target_id': '77'}) for ability in
                  ('eye_shot', 'confusion_shot', 'underhand_shot', 'fast_blast')]
        for action, ability, extra in cases:
            with self.subTest(action=action, ability=ability):
                self.request(action, ability, **extra, damage=9999, reduction=1,
                             learned=True, armed_until=9999, speed_bonus=999,
                             target_ids=['77', '78'], homing_cone_degrees=360)
                self.assertEqual(self.command()['ability_id'], ability)
                for key in ('damage', 'reduction', 'learned', 'armed_until', 'speed_bonus',
                            'target_ids', 'homing_cone_degrees'):
                    self.assertNotIn(key, self.command())

    def test_gestures_reject_wrong_target_ownership_and_pose(self):
        cases = [('underhand_shot', {'target_id': '77'}),
                 ('underhand_shot', {'two_hands': False}),
                 ('duelist_stance', {}), ('duelist_stance', {'target_id': '0'}),
                 ('duelist_stance', {'target_id': '７７'}),
                 ('underhand_shot', {'two_hands': 1}),
                 ('underhand_shot', {'origin': [0, float('nan'), 0]}),
                 ('underhand_shot', {'shot_id': 'bad token'}),
                 ('underhand_shot', {'character_id': '43'}),
                 ('underhand_shot', {'session_id': 'someone-else'}),
                 ('spray_shot', {}), ('fireLightningCone2', {})]
        for ability, extra in cases:
            with self.subTest(ability=ability, extra=extra), self.assertRaises((ValueError, RuntimeError)):
                self.request('bountyhunter', ability, **extra)
        self.hub._exchange.assert_not_called()

    def test_bh_fire_requires_target_and_carbine_support(self):
        for ability in ('eye_shot', 'confusion_shot', 'underhand_shot', 'fast_blast'):
            for target in (None, '', '0', '18446744073709551616', '７７', 77):
                with self.subTest(ability=ability, target=target), self.assertRaises(ValueError):
                    self.request('fire', ability, target_id=target)
        for ability in ('confusion_shot', 'underhand_shot'):
            with self.assertRaises(ValueError):
                self.request('fire', ability, target_id='77', two_hands=False)
        for ability in ('duelist_stance', 'spray_shot', 'fireLightningCone1'):
            with self.assertRaises(ValueError):
                self.request('fire', ability, target_id='77')
        self.hub._exchange.assert_not_called()
        self.request('fire', 'underhand_shot')
        self.assertNotIn('target_id', self.command())

    def test_guidance_is_only_a_target_intent(self):
        self.request('fire', guided_target_id='77', homing_turn_rate=999, homing=True)
        self.assertEqual(self.command()['guided_target_id'], '77')
        self.assertNotIn('homing_turn_rate', self.command())
        for action in ('impact', 'bountyhunter', 'update'):
            with self.assertRaises(ValueError):
                contact_fields({'guided_target_id': '77'}, action)
        for target in ('0', '18446744073709551616', '７７', 77, None):
            with self.assertRaises(ValueError):
                contact_fields({'guided_target_id': target}, 'fire')

    def test_pellets_forward_unique_contact_geometry_without_damage_claims(self):
        contacts = [dict(pellet_index=i, hit_position=[0, 1, -8], projectile_age_seconds=.05)
                    for i in range(8)]
        self.request('impact', target_id='77', hit_position=[0, 1, -8],
                     projectile_age_seconds=.05, pellet_contacts=contacts, pellet_damage=999)
        self.assertEqual(self.command()['pellet_contacts'], contacts)
        self.assertNotIn('pellet_damage', self.command())
        contacts[0]['hit_position'][0] = 100
        self.assertEqual(self.command()['pellet_contacts'][0]['hit_position'][0], 0)

    def test_pellets_reject_duplicates_nonfinite_and_cross_route(self):
        base = dict(pellet_index=0, hit_position=[0, 1, -8], projectile_age_seconds=.05)
        cases = [[], [base] * 2, [base] * 9, [dict(base, pellet_index=-1)],
                 [dict(base, pellet_index=8)], [dict(base, pellet_index=True)],
                 [dict(base, target_id='78')], [dict(base, damage=100)],
                 [dict(base, hit_position=[0, float('inf'), 0])],
                 [dict(base, projectile_age_seconds=-1)],
                 [dict(base, projectile_age_seconds=8.01)],
                 [dict(base, projectile_age_seconds=float('nan'))]]
        for contacts in cases:
            with self.subTest(contacts=contacts), self.assertRaises(ValueError):
                contact_fields({'pellet_contacts': contacts}, 'impact')
        with self.assertRaises(ValueError):
            contact_fields({'pellet_contacts': [base]}, 'fire')


if __name__ == '__main__':
    unittest.main()
