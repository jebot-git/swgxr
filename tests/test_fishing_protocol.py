import math, unittest
from server.services_protocol import command, MUTATIONS
from server.remote_gateway import POST

class FishingProtocolTests(unittest.TestCase):
 def request(self,action,**values):
  return command('fishing_'+action,dict(rod_id='42',request_id='fish-test-0001',**values))
 def test_routes_and_read_only_status(self):
  for name in ('status','open','bait','cast','action','stop','stow','collect'):
   self.assertIn('/services/fishing_'+name,POST)
  self.assertNotIn('fishing_status',MUTATIONS)
  self.assertEqual(command('fishing_status',{'rod_id':'42'})['rod_id'],'42')
 def test_owned_ids_and_receipts(self):
  for bad in (None,42,True,'0','-1','١٢',str(2**64)):
   with self.subTest(bad=bad),self.assertRaises(ValueError):command('fishing_status',{'rod_id':bad})
  with self.assertRaises(ValueError):command('fishing_bait',{'rod_id':'42','bait_id':'44'})
  self.assertEqual(self.request('bait',bait_id='44')['bait_id'],'44')
 def test_physical_cast_no_reward_or_freshness_authority(self):
  out=self.request('cast',cast_position=[10,0,12],fish='rare',freshness=0,quality=100,success=True,jump=True)
  self.assertEqual(out['cast_position'],[10,0,12])
  for field in ('fish','freshness','quality','success','jump'):self.assertNotIn(field,out)
  for bad in ([0,0],[0,math.nan,0],[True,0,0],[0,math.inf,0],[8193,0,0]):
   with self.subTest(bad=bad),self.assertRaises(ValueError):self.request('cast',cast_position=bad)
 def test_gestures_are_bounded_and_bound_to_attempt(self):
  for value in range(1,5):self.assertEqual(self.request('action',gesture=value,session_id='fish-cast-0001')['gesture'],value)
  for bad in (0,5,-1,1.0,True,'reel'):
   with self.subTest(bad=bad),self.assertRaises(ValueError):self.request('action',gesture=bad,session_id='fish-cast-0001')
  with self.assertRaises(ValueError):self.request('action',gesture=4)
 def test_stop_is_not_an_action_that_can_be_delayed_in_queue(self):
  self.assertNotIn('gesture',self.request('stop',gesture=4))
  with self.assertRaises(ValueError):self.request('jump')
if __name__=='__main__':unittest.main()
