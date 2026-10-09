import unittest
from unittest.mock import Mock
from server.live_combat import LiveCombatHub, LiveConflict
from server.remote_gateway import POST

class WarcryProtocol(unittest.TestCase):
    def setUp(self):
        self.hub = LiveCombatHub()
        self.hub.sessions['one'] = dict(id='session_one', account='one', character_id='1', process=Mock())
        self.hub.sessions['one']['process'].poll.return_value = None
        self.hub._exchange = Mock(return_value={'session_live': True})
        self.request = dict(character_id='1', session_id='session_one', shot_id='gesture_1', item_id='42', origin=[0,1.7,0], direction=[0,0,1])

    def tearDown(self):
        self.hub.sessions.clear()

    def test_route_and_authoritative_fields(self):
        self.assertIn('/combat/session/warcry', POST)
        self.hub.request('one', 'warcry', self.request | {'target_id':'999','damage':999,'rank':2})
        command = self.hub._exchange.call_args.args[1]
        self.assertEqual(command['action'], 'warcry')
        self.assertEqual(command['item_id'], '42')
        for key in ('target_id','damage','rank'): self.assertNotIn(key, command)

    def test_ownership(self):
        with self.assertRaises(LiveConflict):
            self.hub.request('one', 'warcry', self.request | {'character_id':'2'})
        self.hub._exchange.assert_not_called()

    def test_required_weapon_and_finite_pose(self):
        for changes in ({'origin':[float('nan'),0,0]}, {'direction':[0,0]}, {'item_id':'bad'}):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                self.hub.request('one', 'warcry', self.request | changes)
        request=self.request.copy();del request['item_id']
        with self.assertRaises(ValueError):self.hub.request('one','warcry',request)
        self.hub._exchange.assert_not_called()

    def test_brawler_routes_and_targets(self):
        self.assertIn('/combat/session/brawler_buff', POST)
        self.hub.request('one','brawler_buff',self.request | {'ability_id':'center_of_being'})
        command=self.hub._exchange.call_args.args[1]
        self.assertEqual(command['ability_id'],'center_of_being')
        self.assertNotIn('origin',command)
        for ability in ('knockdown_strike','unarmed_stun','unarmed_blind','polearm_stun'):
            self.hub.request('one','melee',self.request | {'ability_id':ability,'target_id':'55'})
            command=self.hub._exchange.call_args.args[1]
            self.assertEqual(command['ability_id'],ability)
            self.assertEqual(command['target_id'],'55')
        for action, extra in [('melee',{'ability_id':'unarmed_stun'}),('melee',{'ability_id':'unarmed_stun','target_id':'wrong'}),('brawler_buff',{'ability_id':'last_ditch'}),('fire',{'ability_id':'knockdown_strike'})]:
            with self.subTest(action=action,extra=extra), self.assertRaises(ValueError):
                self.hub.request('one',action,self.request | extra)

    def test_cannot_fire_warcry_as_projectile(self):
        with self.assertRaises(ValueError):self.hub.request('one','fire',self.request | {'ability_id':'warcry'})
        self.hub._exchange.assert_not_called()

if __name__ == '__main__':unittest.main()
