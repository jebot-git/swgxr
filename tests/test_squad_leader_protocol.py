"""Owned Squad Leader casts and explicit per-member Volley Fire intent."""
import unittest
from unittest.mock import Mock

from server.live_combat import LiveCombatHub
from server.scout_protocol import command as scout_command
from server.squad_leader_protocol import ABILITIES, mark_intent


class SquadLeaderProtocolTests(unittest.TestCase):
    def setUp(self):
        self.hub = LiveCombatHub()
        self.hub.sessions['leader'] = dict(account='leader', character_id='42', id='session_leader')
        self.hub._exchange = Mock(return_value={'session_live': True})
        self.cast = dict(character_id='42', session_id='session_leader', item_id='55',
                         shot_id='leader-123', ability_id='steady_aim', target_id='77',
                         origin=[0, 1.7, 0], direction=[0, 0, -1])
        self.mark = dict(volley_mark_id='volley_42_123456789', volley_target_id='77')

    def tearDown(self):
        self.hub.sessions.clear()

    def request(self, action='squadleader', **extra):
        self.hub.request('leader', action, dict(self.cast, **extra))
        return self.hub._exchange.call_args.args[1]

    def test_all_support_casts_forward_intent_only(self):
        for ability in ABILITIES:
            with self.subTest(ability=ability):
                payload = self.request(ability_id=ability, group_id='999', member_ids=['78'],
                                       damage_multiplier=99, duration_seconds=999,
                                       guaranteed=True, remaining_hits=100)
                self.assertEqual(payload['ability_id'], ability)
                self.assertEqual(payload['target_id'], '77')
                self.assertNotIn('two_hands', payload)
                for key in ('group_id', 'member_ids', 'damage_multiplier', 'duration_seconds',
                            'guaranteed', 'remaining_hits'):
                    self.assertNotIn(key, payload)

    def test_cast_ownership_identity_and_finite_pose(self):
        for fields in ({'ability_id':'rally_all'}, {'ability_id':'volleyFire'},
                       {'target_id':'0'}, {'target_id':'７７'}, {'item_id':'0'},
                       {'target_id':str(2**64)}, {'shot_id':'short'},
                       {'origin':[0, float('nan'), 0]}, {'direction':[False, 0, 1]},
                       {'character_id':'43'}, {'session_id':'foreign'}, self.mark):
            with self.subTest(fields=fields), self.assertRaises(ValueError):
                self.request(**fields)

    def test_mark_intent_reaches_every_damaging_route(self):
        abilities = {'fire':'lethal_shot', 'melee':'unarmed_stun', 'commando':'focused_discharge',
                     'tka':'tka_sweep', 'swordsman':'rending_cut', 'fencer':'arterial_cut',
                     'pikeman':'polearm_stun', 'pistoleer':'fan_shot', 'carbineer':'full_auto_sweep'}
        for action, ability in abilities.items():
            payload = dict(self.cast, ability_id=ability, two_hands=True, **self.mark)
            if action in ('tka', 'pistoleer', 'carbineer'):
                payload.pop('target_id')
            with self.subTest(action=action):
                self.hub.request('leader', action, payload)
                actual = self.hub._exchange.call_args.args[1]
                self.assertEqual({k:actual[k] for k in self.mark}, self.mark)
        payload = dict(self.cast, **self.mark)
        for key in ('target_id', 'ability_id'):
            payload.pop(key)
        for action in ('fire', 'melee'):
            self.hub.request('leader', action, payload)
            self.assertEqual(self.hub._exchange.call_args.args[1]['volley_target_id'], '77')

    def test_marks_cannot_be_spent_by_self_buffs_or_unrelated_actions(self):
        for action, ability in [('rifleman','rifleman_focus'), ('commando','overdrive'),
                                ('tka','indomitable_focus'), ('fencer','flawless_assault'),
                                ('pistoleer','run_and_gun'), ('carbineer','tactical_brace'),
                                ('taunt',''), ('warcry',''), ('impact',''), ('update',''),
                                ('squadleader','volley_fire')]:
            with self.subTest(action=action, ability=ability), self.assertRaises(ValueError):
                mark_intent(self.mark, action, ability)
        for fields in ({'volley_mark_id':'short'}, {'volley_target_id':'0'},
                       {'volley_target_id':'７７'}, {'volley_mark_id':'a'*81},
                       {'volley_mark_id':'x\ny'}, {'volley_target_id':True}):
            with self.subTest(fields=fields), self.assertRaises(ValueError):
                mark_intent(dict(self.mark, **fields), 'fire')
        for key in self.mark:
            with self.assertRaises(ValueError):
                mark_intent({key:self.mark[key]}, 'fire')
        with self.assertRaises(ValueError):
            mark_intent(self.mark, 'fire', target_id='78')
        self.assertEqual(mark_intent({}, 'update'), {})

    def test_volley_fire_mark_is_independent_of_multishot_receipt(self):
        payload = self.request('fire', ability_id='flurry_shot', volley_id='leader-123',
                               volley_index=0, **self.mark)
        self.assertEqual(payload['volley_id'], 'leader-123')
        self.assertEqual(payload['volley_mark_id'], self.mark['volley_mark_id'])
        with self.assertRaises(ValueError):
            self.request('fire', ability_id='flurry_shot', volley_id='leader-123',
                         volley_index=0, volley_mark_id=self.mark['volley_mark_id'])

    def test_grenade_keeps_native_fuse_and_damage_authority(self):
        data = dict(position=[0,0,0], request_id='grenade-123', item_id='55', target_id='77',
                    guaranteed=True, damage=999, fuse_seconds=0, **self.mark)
        payload = scout_command('grenade', data)
        self.assertEqual({k:payload[k] for k in self.mark}, self.mark)
        for key in ('guaranteed','damage','fuse_seconds'):
            self.assertNotIn(key, payload)
        with self.assertRaises(ValueError):
            scout_command('grenade', dict(data, target_id='78'))
        self.assertEqual(scout_command('trap', data)['volley_mark_id'], self.mark['volley_mark_id'])
        with self.assertRaises(ValueError):
            scout_command('mask_scent', data)


if __name__ == '__main__':
    unittest.main()
