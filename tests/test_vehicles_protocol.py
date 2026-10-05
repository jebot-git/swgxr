import unittest
from server.vehicles_protocol import command,controls,vector
class VehiclesProtocol(unittest.TestCase):
 def test_seat(self):
  self.assertEqual(command('board',{'vehicle_id':'123','seat':'passenger','hand':[1,2,3]})['seat'],'passenger')
  for seat in ('pilot',0,None):
   with self.assertRaises(ValueError):command('board',{'vehicle_id':'123','seat':seat,'hand':[1,2,3]})
 def test_id(self):
  for value in ('0','-1','1.0',2**64,str(2**64)):
   with self.assertRaises(ValueError):command('call',{'device_id':value})
 def test_controls(self):
  self.assertEqual(controls({'held':False,'throttle':1,'steer':1}),{'held':False,'throttle':0,'steer':0})
  for value in (float('nan'),float('inf'),2,True):
   with self.assertRaises(ValueError):controls({'held':True,'throttle':value,'steer':0})
 def test_two_hands(self):
  with self.assertRaises(ValueError):command('store',{'device_id':'10','left':[1,2,3]})
  self.assertEqual(command('store',{'device_id':'10','left':[1,2,3],'right':[3,2,1]})['right'],[3,2,1])
 def test_no_client_authority(self):
  self.assertEqual(command('call',{'device_id':'10','owned':True,'max_speed':1000}),{'action':'call','device_id':'10'})
 def test_activation_stable_identity(self):
  q=command('activate',{'item_id':'10','request_id':'receipt_123','position':[1,2,3],'building_id':'0','cell_index':0,'owned':True})
  self.assertEqual(q,{'action':'activate','item_id':'10','request_id':'receipt_123','position':[1,2,3],'building_id':'0','cell_index':0})
  for value in ('', 'bad space', 'x'*65):
   with self.assertRaises(ValueError):command('activate',{'item_id':'10','request_id':value})
 def test_snapshot_does_not_alias_live_receipt(self):
  from server.vehicles_protocol import snapshot
  native={"source_kind":"core3_vehicles","character_id":"1","state":{"character_id":"1","vehicles":[]},"mutation":{"success":True}}
  live={"mutation":native};out=snapshot(native,"1");out["live_response"]=live
  import json
  self.assertTrue(json.dumps(out));self.assertNotIn("live_response",native)
 def test_activation_receipt_confirmed_rejection(self):
  from server.vehicles_protocol import snapshot,ConfirmedVehicleRejection
  with self.assertRaises(ConfirmedVehicleRejection) as caught:snapshot({'error':'outside required','confirmed_rejection':True},'10')
  self.assertFalse(caught.exception.mutation_started)
  with self.assertRaises(ValueError) as caught:snapshot({'error':'transport failed'},'10')
  self.assertFalse(getattr(caught.exception,'confirmed_rejection',False))
 def test_recall_and_droid_ownership_inputs(self):
  for action in ('recall','pet_call','pet_recall'):
   self.assertEqual(command(action,{'device_id':'12','owned':True,'force':True}),{'action':action,'device_id':'12'})
   with self.assertRaises(ValueError):command(action,{'device_id':'0'})
 def test_droid_grab_needs_both_finite_hands(self):
  for hands in ({'left':[1,2,3]},{'left':[1,2,3],'right':[float('nan'),0,0]}):
   with self.assertRaises(ValueError):command('pet_store',dict(device_id='12',**hands))
  self.assertEqual(command('pet_store',{'device_id':'12','left':[1,2,3],'right':[3,2,1]})['right'],[3,2,1])
if __name__=='__main__':unittest.main()
