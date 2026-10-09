import unittest
from unittest.mock import Mock
from server.live_combat import LiveCombatHub
from server.remote_gateway import POST
from server.combat_loadout_protocol import validate

class TkaProtocol(unittest.TestCase):
    def setUp(self):
        self.hub=LiveCombatHub()
        self.hub.sessions['tka']={'account':'tka','character_id':'42','id':'session_tka'}
        self.hub._exchange=Mock(return_value={'session_live':True})
    def tearDown(self):self.hub.sessions.clear()
    def request(self,ability,**extra):
        fields=dict(character_id='42',session_id='session_tka',shot_id='tka-1',item_id='55',ability_id=ability,origin=[0,1.7,0],direction=[0,0,-1])
        fields.update(extra)
        return self.hub.request('tka','tka',fields)
    def test_registered_ids_and_server_owned_targets(self):
        for ability in ('tka_sweep','tka_half_spin','tka_volley','indomitable_focus'):
            self.request(ability,target_ids=['666'],damage=999999,max_targets=500,duration=999)
            command=self.hub._exchange.call_args.args[1]
            self.assertEqual(command['ability_id'],ability)
            for key in ('target_ids','damage','max_targets','duration'):self.assertNotIn(key,command)
    def test_bad_id_pose_and_ownership(self):
        for ability in ('force_of_will','challenging_strike','admin',None,42):
            with self.assertRaises(ValueError):self.request(ability)
        for extra in ({'origin':[float('nan'),0,0]},{'direction':[0,0]},{'character_id':'43'},{'session_id':'other'},{'item_id':55}):
            with self.assertRaises((ValueError,RuntimeError)):self.request('tka_sweep',**extra)
    def test_challenge_requires_bound_melee_target(self):
        fields=dict(character_id='42',session_id='session_tka',shot_id='tka-2',item_id='55',ability_id='challenging_strike',origin=[0,1.7,0],direction=[0,0,-1])
        with self.assertRaises(ValueError):self.hub.request('tka','melee',fields)
        self.hub.request('tka','melee',dict(fields,target_id='123'))
        self.assertEqual(self.hub._exchange.call_args.args[1]['target_id'],'123')
    def test_route_and_unarmed_loadout(self):
        self.assertIn('/combat/session/tka',POST)
        value={'family':'unarmed','slots':['challenging_strike','unarmed_stun','knockdown_strike','unarmed_blind'],'ultimate':'indomitable_focus','revision':0}
        self.assertEqual(validate(value),value)

if __name__=='__main__':unittest.main()
