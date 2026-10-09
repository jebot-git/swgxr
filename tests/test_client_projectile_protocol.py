import unittest
from unittest.mock import Mock
from server.live_combat import LiveCombatHub
class ClientProjectileProtocol(unittest.TestCase):
 def setUp(self):
  self.hub=LiveCombatHub();self.hub.sessions['shot']={'account':'shot','character_id':'42','id':'projectile'};self.hub._exchange=Mock(return_value={'session_live':True})
 def tearDown(self):self.hub.sessions.clear()
 def fire(self,**kw):
  q=dict(character_id='42',session_id='projectile',shot_id='s1',item_id='55',origin=[0,1.7,0],direction=[0,0,-1],two_hands=True,firing_posture='prone');q.update(kw);return self.hub.request('shot','fire',q)
 def test_posture_and_grip_only_no_damage_authority(self):
  self.fire(damage=999,range_scale=99,range_damage_multiplier=99,accuracy=999)
  q=self.hub._exchange.call_args.args[1];self.assertTrue(q['two_hands']);self.assertEqual(q['firing_posture'],'prone')
  for key in ('damage','range_scale','range_damage_multiplier','accuracy'):self.assertNotIn(key,q)
 def test_bad_context_rejected(self):
  for kw in ({'two_hands':1},{'two_hands':'true'},{'firing_posture':'flying'},{'firing_posture':None},{'direction':[0,float('nan'),0]},{'session_id':'other'}):
   with self.assertRaises((ValueError,RuntimeError)):self.fire(**kw)
  self.hub._exchange.assert_not_called()
