import unittest
from server.vehicles_protocol import command, snapshot
from server.remote_gateway import POST

class PetCommands(unittest.TestCase):
 def body(self, number=1, **extra):
  return dict(device_id='123',command_id=number,request_id='pet_command_001',**extra)
 def test_command_range_and_identity(self):
  for number in [0,25,True,1.5,'1',None]:
   with self.subTest(number=number),self.assertRaises(ValueError):command('pet_command',self.body(number))
  for key in ['device_id','request_id']:
   body=self.body();body.pop(key)
   with self.assertRaises(ValueError):command('pet_command',body)
 def test_targeted_commands_require_native_target(self):
  for number in (3,4,5,6,12,13,17,18,19,20,21):
   with self.subTest(number=number):
    self.assertEqual(command('pet_command',self.body(number,target_id='456'))['target_id'],'456')
    for target in [None,'','0',456,'-1',str(2**64),'１２３']:
     with self.assertRaises(ValueError):command('pet_command',self.body(number,target_id=target))
 def test_untargeted_commands_never_adopt_weapon_target(self):
  for number in (1,2,7,8,9,10,11,14,15,16,22,23,24):
   self.assertNotIn('target_id',command('pet_command',self.body(number)))
   with self.assertRaises(ValueError):command('pet_command',self.body(number,target_id='456'))
 def test_recovery_still_requires_two_hand_evidence(self):
  with self.assertRaises(ValueError):command('pet_store',{'device_id':'123','left':[0,1,0]})
  out=command('pet_store',{'device_id':'123','left':[0,1,0],'right':[.2,1,0]})
  self.assertEqual(out['right'],[.2,1,0])
 def test_gateway_and_owner_snapshot(self):
  self.assertIn('/vehicles/pet_command',POST)
  with self.assertRaises(ValueError):snapshot({'source_kind':'core3_vehicles','character_id':'1','state':{'character_id':'2'}},'1')
if __name__=='__main__':unittest.main()
