"""Bounty intent validation keeps targets, consumables and rewards native."""
import unittest
from unittest.mock import patch

from server.bounty_protocol import ACTIONS, FIELDS
from server.services_protocol import MUTATIONS, command, snapshot
from server.remote_gateway import POST


class BountyProtocolTests(unittest.TestCase):
    def data(self, action, **changes):
        out = dict(request_id='bounty-request-001', **{FIELDS[action]: '42'})
        if action == 'bounty_probe':
            out['search_planet'] = 'naboo'
        out.update(changes)
        return out

    def test_all_actions_require_receipts_and_are_routable(self):
        for action in ACTIONS:
            with self.subTest(action=action):
                self.assertIn(action, MUTATIONS)
                self.assertIn('/services/' + action, POST)
                self.assertEqual(command(action, self.data(action)),
                                 dict(action=action, **self.data(action)))
                for key in ('', 'short', 'invalid key', 'x'*65, None, 123):
                    with self.assertRaises(ValueError):
                        command(action, dict(self.data(action), request_id=key))

    def test_exact_native_object_ids(self):
        for action in ACTIONS:
            for value in (None, True, 42, 4.2, '', '0', '-42', '４２', '4 2', str(2**64)):
                with self.subTest(action=action, value=value), self.assertRaises(ValueError):
                    command(action, dict(self.data(action), **{FIELDS[action]: value}))
            self.assertEqual(command(action, dict(self.data(action), **{FIELDS[action]: str(2**64-1)}))[FIELDS[action]], str(2**64-1))

    def test_authority_claims_are_not_forwarded(self):
        for action in ACTIONS:
            payload = self.data(action, terminal_id='123', mission_id='999',
                                target_planet='naboo', target_position=[1, 2, 3],
                                player_target=True, signature=True, success=True,
                                charges=99, reward=999999, stage='complete',
                                delay_seconds=0, droid_skill=1000)
            self.assertEqual(command(action, payload), dict(action=action, **self.data(action)))

    def test_reuses_ground_planet_and_cell_fences(self):
        from server.planets import SUPPORTED_PLANETS
        for planet in SUPPORTED_PLANETS:
            request = self.data('bounty_probe', planet=planet, zone=planet,
                                position=[1, 2, 3], building_id='0', cell_index=0)
            self.assertEqual(command('bounty_probe', request)['planet'], planet)
        for extra in ({'planet':'space_tatooine'}, {'planet':'mustafar'},
                      {'planet':'tatooine','zone':'naboo'}, {'position':[0,float('nan'),0]},
                      {'building_id':'0','cell_index':3}):
            with self.subTest(extra=extra), self.assertRaises(ValueError):
                command('bounty_probe', self.data('bounty_probe', **extra))

    def test_no_player_bounty_or_client_completion_verbs(self):
        for action in ('bounty_player', 'bounty_complete', 'bounty_reward', 'bounty_spawn', 'bounty_locate', 'bounty_transmit'):
            with self.assertRaises(ValueError):
                command(action, dict(request_id='bounty-request-001', target_id='42'))
            self.assertNotIn('/services/' + action, POST)

    def test_probe_destination_is_separate_from_source_zone(self):
        value = command('bounty_probe', self.data('bounty_probe', planet='tatooine', zone='tatooine'))
        self.assertEqual(value['search_planet'], 'naboo')
        self.assertEqual(value['planet'], 'tatooine')
        for destination in (None, '', 'space_tatooine', 'mustafar', True, ['naboo'], 'Naboo'):
            with self.subTest(destination=destination), self.assertRaises(ValueError):
                command('bounty_probe', self.data('bounty_probe', search_planet=destination))

    def test_native_snapshot_discovery_and_original_labels(self):
        bounty = dict(pve_only=True, mission_id='17', stage='signature', signature=True,
                      planet_known=False, planet='', planets=['tatooine','naboo'],
                      message='@mission/mission_generic:bounty_no_signature',
                      droids=[{'id':'23','kind':'probe','uses':2,'call_enabled':True}],
                      informants=[{'id':'31','name':'@mob/creature_names:informant'}],
                      waypoint={'active':False,'planet':'','position':[]})
        raw = dict(source_kind='core3_services', character_id='42', bounty=bounty)
        with patch('server.services_protocol.display', side_effect=lambda table,key,fallback:'resolved '+key):
            value = snapshot(raw, '42')['state']['bounty']
        self.assertEqual(value['message'], 'resolved bounty_no_signature')
        self.assertEqual(value['informants'][0]['name'], 'resolved informant')
        self.assertEqual(value['waypoint']['position'], [])
        self.assertFalse(value['planet_known'])
        self.assertEqual(raw['bounty']['informants'][0]['name'], '@mob/creature_names:informant')
        raw['bounty']['waypoint'] = dict(active=True, planet='naboo', position=[1,2,3])
        self.assertEqual(snapshot(raw, '42')['state']['bounty']['waypoint']['position'], [1,2,3])
        with self.assertRaises(ValueError):
            snapshot(raw, '43')

    def test_snapshot_bounds_and_pve_scope(self):
        for bad in ({'pve_only':False}, {'droids':[{'id':'1'}]*257},
                    {'informants':[{'id':'1'}]*129}, {'planets':['naboo']*11},
                    {'planets':['naboo','naboo']}, {'planets':['mustafar']},
                    {'droids':[{'id':'０'}]}, {'informants':[{'id':'0'}]},
                    {'waypoint':{'active':True,'planet':'naboo','position':[0,float('nan'),0]}}):
            raw = dict(source_kind='core3_services', character_id='42', bounty=dict(pve_only=True))
            raw['bounty'].update(bad)
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                snapshot(raw, '42')


if __name__ == '__main__':
    unittest.main()
