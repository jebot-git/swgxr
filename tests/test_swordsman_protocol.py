import unittest
from unittest.mock import Mock
from server.live_combat import LiveCombatHub
from server.remote_gateway import POST

class SwordsmanProtocol(unittest.TestCase):
 def setUp(self):
  self.hub=LiveCombatHub();self.hub.sessions['sword']={'account':'sword','character_id':'42','id':'session_sword'}
  self.hub._exchange=Mock(return_value={'session_live':True})
 def tearDown(self):self.hub.sessions.clear()
 def request(self,ability,**extra):
  fields=dict(character_id='42',session_id='session_sword',shot_id='sword-1',item_id='55',ability_id=ability,origin=[0,1.7,0],direction=[0,0,-1]);fields.update(extra)
  return self.hub.request('sword','swordsman',fields)
 def test_targeted_attacks_bound_to_one_native_target(self):
  for ability in ('rending_cut','disrupting_blow','hamstring','decisive_strike','armour_break'):
   with self.assertRaises(ValueError):self.request(ability)
   self.request(ability,target_id='123',boss=False,level=1,health=1,damage=9999,armour_score=0,duration=999)
   payload=self.hub._exchange.call_args.args[1]
   self.assertEqual(payload['target_id'],'123')
   for key in ('boss','level','health','damage','armour_score','duration'):self.assertNotIn(key,payload)
 def test_gestures_select_targets_only_on_server(self):
  for ability in ('overhead_cleave','ground_slam'):
   with self.assertRaises(ValueError):self.request(ability,target_id='123')
   self.request(ability,target_ids=['123','124'],max_targets=999)
   payload=self.hub._exchange.call_args.args[1]
   self.assertNotIn('target_ids',payload);self.assertNotIn('max_targets',payload)
 def test_reject_forged_identity_id_and_pose(self):
  for ability in ('admin','tka_sweep',None,1):
   with self.assertRaises(ValueError):self.request(ability)
  for extra in ({'origin':[float('nan'),0,0]},{'direction':[0,0]},{'character_id':'43'},{'session_id':'other'},{'item_id':55}):
   with self.assertRaises((ValueError,RuntimeError)):self.request('overhead_cleave',**extra)
  with self.assertRaises(ValueError):self.request('decisive_strike',target_id=-1)
 def test_remote_route(self):self.assertIn('/combat/session/swordsman',POST)
