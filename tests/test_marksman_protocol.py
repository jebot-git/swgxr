import unittest
from unittest.mock import Mock
from server.live_combat import LiveCombatHub

class MarksmanProtocol(unittest.TestCase):
 def setUp(self):
  self.hub=LiveCombatHub();self.hub.sessions['marksman']={'account':'marksman','character_id':'42','id':'live'};self.hub._exchange=Mock(return_value={'session_live':True})
 def tearDown(self):self.hub.sessions.clear()
 def fire(self,ability,**changes):
  q=dict(character_id='42',session_id='live',shot_id='s1',item_id='55',origin=[0,1.7,0],direction=[0,0,-1],two_hands=True,firing_posture='standing',ability_id=ability,target_id='77');q.update(changes);return self.hub.request('marksman','fire',q)
 def test_four_bound_abilities_and_no_client_effect_authority(self):
  for ability in ('suppression_fire','warning_shot','controlled_burst','bleeding_shot'):
   self.fire(ability,damage=999,hit_count=99,bleed_budget=999,effects=['kill'],action_cost=0,cooldown_seconds=0)
   q=self.hub._exchange.call_args.args[1]
   self.assertEqual(q['ability_id'],ability);self.assertEqual(q['target_id'],'77')
   for key in ('damage','hit_count','bleed_budget','effects','action_cost','cooldown_seconds'):self.assertNotIn(key,q)
 def test_target_required_and_retired_commands_rejected(self):
  for ability in ('suppression_fire','warning_shot','controlled_burst','bleeding_shot'):
   with self.assertRaises(ValueError):self.fire(ability,target_id='')
  for ability in ('threaten_shot','aim','fullAutoSingle1','healthShot1'):
   with self.assertRaises(ValueError):self.fire(ability)
  self.hub._exchange.assert_not_called()
 def test_invalid_owner_and_target(self):
  for changes in ({'character_id':'99'},{'session_id':'bad'},{'target_id':'not-id'},{'target_id':'18446744073709551616'}):
   with self.assertRaises((ValueError,RuntimeError)):self.fire('bleeding_shot',**changes)
  self.hub._exchange.assert_not_called()
