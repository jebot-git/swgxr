import unittest
from server.vehicles_protocol import command, snapshot

class CreatureHandlerProtocolTests(unittest.TestCase):
 def test_status_and_original_ids(self):
  self.assertEqual(command('ch_status',{'zone':'tatooine'}),{'action':'ch_status','zone':'tatooine'})
  got=command('ch_tame',{'target_id':'123','request_id':'tame_once_123','force':True,'adult':True,'skill':999,'chance':100})
  self.assertEqual(got,{'action':'ch_tame','target_id':'123','request_id':'tame_once_123'})
 def test_ids_are_ascii(self):
  with self.assertRaises(ValueError):command('ch_tame',{'target_id':'１２３','request_id':'tame_once_123'})
 def test_receipts_required_for_all_mutations(self):
  for action in ('ch_tame','ch_embolden','ch_enrage','ch_train_mount','ch_train_command'):
   with self.subTest(action=action),self.assertRaises(ValueError):command(action,{'target_id':'123','device_id':'456'})
 def test_mount_touch_finite(self):
  self.assertEqual(command('ch_train_mount',{'device_id':'456','request_id':'mount_once_1','hand':[1,2,3]})['hand'],[1,2,3])
  for hand in ([0,float('nan'),0],[1,2],[10001,0,0]):
   with self.assertRaises(ValueError):command('ch_train_mount',{'device_id':'456','request_id':'mount_once_1','hand':hand})
 def test_only_original_creature_train_commands(self):
  for number in (1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,18,22,23):
   self.assertEqual(command('ch_train_command',{'device_id':'123','request_id':'training123','command_id':number})['command_id'],number)
  for number in (0,17,19,20,21,24,True,'3'):
   with self.assertRaises(ValueError):command('ch_train_command',{'device_id':'123','request_id':'training123','command_id':number})
 def test_source_ownership_and_bounds(self):
  out={'character_id':'123','source_kind':'core3_vehicles','state':{'character_id':'123','creature_handler':{'candidates':[{}]*32}},'mutation':{'success':True}}
  self.assertEqual(len(snapshot(out,'123')['state']['creature_handler']['candidates']),32)
  with self.assertRaises(ValueError):snapshot(out,'124')
  out['state']['creature_handler']['candidates'].append({})
  with self.assertRaises(ValueError):snapshot(out,'123')
