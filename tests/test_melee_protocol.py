import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock
from server.live_combat import LiveCombatHub, LiveConflict


class MeleeProtocolTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.hub = LiveCombatHub()
        process = Mock()
        process.poll.return_value = None
        self.hub.sessions['owner'] = dict(id='owned', account='owner', character_id='123', folder=Path(self.temp.name), options=Path(self.temp.name)/'options', process=process)
        self.hub._exchange = Mock(return_value={'session_live': True})
        self.addCleanup(self.hub.close)
        self.data = dict(character_id='123', session_id='owned', shot_id='s1', item_id='456', origin=[0,1,0], direction=[0,0,1])

    def test_only_intent_is_forwarded(self):
        self.hub.request('owner', 'melee', dict(self.data, target_id='999', damage=99999, ability_id='kill', hit=True))
        command = self.hub._exchange.call_args.args[1]
        self.assertEqual(command['action'], 'melee')
        for key in ('shot_id', 'item_id', 'origin', 'direction'):
            self.assertEqual(command[key], self.data[key])
        for key in ('target_id', 'damage', 'ability_id', 'hit'):
            self.assertNotIn(key, command)

    def test_foreign_identity_is_rejected(self):
        for change in ({'character_id':'999'}, {'session_id':'foreign'}):
            with self.assertRaises(LiveConflict):
                self.hub.request('owner', 'melee', dict(self.data, **change))
        with self.assertRaises(LiveConflict):
            self.hub.request('other', 'melee', self.data)
        self.hub._exchange.assert_not_called()

    def test_invalid_or_missing_intent_is_rejected(self):
        for key, value in [('origin',[0,float('nan'),0]), ('direction',[0,True,0]), ('direction',[0,1]), ('item_id',str(2**64)), ('shot_id','x'*81)]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.hub.request('owner', 'melee', dict(self.data, **{key:value}))
        for key in ('shot_id','item_id','origin','direction'):
            data = dict(self.data)
            del data[key]
            with self.assertRaises(ValueError):
                self.hub.request('owner', 'melee', data)
        self.hub._exchange.assert_not_called()


class TauntProtocolTests(MeleeProtocolTests):
    def test_taunt_sends_aim_without_client_target_or_effect(self):
        self.hub.request('owner', 'taunt', dict(self.data, target_id='999', taunted=True, damage=99999, ability_id='taunt'))
        command = self.hub._exchange.call_args.args[1]
        self.assertEqual(command['action'], 'taunt')
        for key in ('shot_id', 'origin', 'direction'):
            self.assertEqual(command[key], self.data[key])
        for key in ('item_id', 'target_id', 'damage', 'ability_id', 'taunted'):
            self.assertNotIn(key, command)

    def test_taunt_rejects_foreign_and_malformed_requests(self):
        with self.assertRaises(LiveConflict):
            self.hub.request('owner', 'taunt', dict(self.data, session_id='foreign'))
        with self.assertRaises(ValueError):
            self.hub.request('owner', 'taunt', dict(self.data, direction=[0, float('nan'), 1]))
        self.hub._exchange.assert_not_called()

    def test_taunt_gateway_route_is_allowed(self):
        from server.remote_gateway import POST
        self.assertIn('/combat/session/taunt', POST)
