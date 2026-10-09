import unittest
from unittest.mock import Mock
from server.live_combat import LiveCombatHub
from server.remote_gateway import POST

class ForceOfWillProtocol(unittest.TestCase):
 def setUp(self):
  self.hub=LiveCombatHub();self.hub.sessions['will']={'account':'will','character_id':'42','id':'will_session'}
  self.hub._exchange=Mock(return_value={'session_live':True})
 def tearDown(self): self.hub.sessions.clear()
 def request(self,**extra):
  payload=dict(character_id='42',session_id='will_session',action='force_of_will');payload.update(extra)
  return self.hub.request('will','life',payload)
 def test_life_action_has_no_client_effect_authority(self):
  self.request(health=99999,cooldown=0,wounds=0,learned=True,target_id='44',force_of_will={'conditions_met':True})
  sent=self.hub._exchange.call_args.args[1]
  self.assertEqual(sent['action'],'life');self.assertEqual(sent['life_action'],'force_of_will')
  for key in ('health','cooldown','wounds','learned','target_id','force_of_will'):self.assertNotIn(key,sent)
 def test_owner_and_life_allowlist(self):
  for extra in ({'character_id':'43'},{'session_id':'other'},{'action':'meditate'},{'action':'powerboost'},{'action':'resurrect'}):
   with self.assertRaises((RuntimeError,ValueError)):self.request(**extra)
  self.hub._exchange.assert_not_called()
 def test_not_attack_or_ultimate_route(self):
  with self.assertRaises(ValueError):
   self.hub.request('will','tka',dict(character_id='42',session_id='will_session',shot_id='fow',item_id='55',ability_id='force_of_will',origin=[0,1.7,0],direction=[0,0,-1]))
 def test_both_existing_life_routes_remain_available(self):
  for path in ('/session/life','/combat/session/life'):self.assertIn(path,POST)
