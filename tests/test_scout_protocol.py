import unittest
from server.scout_protocol import command,snapshot
class ScoutProtocolTests(unittest.TestCase):
 def test_positions(self):
  for p in [[float('nan'),0,0],[9000,0,0],[0,3000,0],[1,2],['0',0,0]]:
   with self.assertRaises(ValueError):command('status',{'position':p})
 def test_tracked_posture(self):
  self.assertEqual(command('status',dict(position=[0,0,0],posture='prone'))['posture'],'prone')
  with self.assertRaises(ValueError):command('status',dict(position=[0,0,0],posture='dead'))
 def test_owned_ids(self):
  for item in ['',0,'-1','18446744073709551616']:
   with self.assertRaises(ValueError):command('trap',dict(position=[0,0,0],request_id='unique123',item_id=item,target_id='1'))
 def test_mutation_receipt_required(self):
  with self.assertRaises(ValueError):command('burst_run',{'position':[0,0,0]})
 def test_valid_actions(self):
  self.assertEqual(command('trap',dict(position=[1,2,3],request_id='unique123',item_id='10',target_id='11'))['target_id'],'11')
 def test_snapshot_identity(self):
  with self.assertRaises(ValueError):snapshot({'source_kind':'core3_scout','character_id':'12','state':{}},'13')
if __name__=='__main__':unittest.main()
