import unittest
from unittest.mock import Mock
from server.live_combat import LiveCombatHub
from server.remote_gateway import POST
class FencerProtocol(unittest.TestCase):
 def setUp(self):
  self.hub=LiveCombatHub();self.hub.sessions['fencer']={'account':'fencer','character_id':'42','id':'session_fencer'};self.hub._exchange=Mock(return_value={'session_live':True})
 def tearDown(self):self.hub.sessions.clear()
 def request(self,ability,**extra):
  fields=dict(character_id='42',session_id='session_fencer',shot_id='fencer-1',item_id='55',ability_id=ability,origin=[0,1.7,0],direction=[0,0,-1]);fields.update(extra);return self.hub.request('fencer','fencer',fields)
 def test_targeted_attacks_are_bound_and_server_owned(self):
  for ability in ('arterial_cut','nerve_strike','disorienting_thrust','exposing_thrust'):
   with self.assertRaises(ValueError):self.request(ability)
   self.request(ability,target_id='123',damage=999,budget=9999,precision=True,progression=1,duration=999)
   payload=self.hub._exchange.call_args.args[1];self.assertEqual(payload['target_id'],'123')
   for key in ('damage','budget','precision','progression','duration'):self.assertNotIn(key,payload)
 def test_gestures_and_self_ultimate_reject_client_targets(self):
  for ability in ('probing_jabs','raking_slash','guard_bash','flawless_assault'):
   with self.assertRaises(ValueError):self.request(ability,target_id='123')
   self.request(ability,target_ids=['123'],max_targets=999)
   payload=self.hub._exchange.call_args.args[1];self.assertNotIn('target_ids',payload);self.assertNotIn('max_targets',payload)
 def test_bad_identity_pose_id(self):
  for ability in ('admin','rending_cut',None,1):
   with self.assertRaises(ValueError):self.request(ability)
  for extra in ({'origin':[float('nan'),0,0]},{'direction':[0,0]},{'character_id':'43'},{'session_id':'other'},{'item_id':55}):
   with self.assertRaises((ValueError,RuntimeError)):self.request('probing_jabs',**extra)
 def test_route(self):self.assertIn('/combat/session/fencer',POST)
