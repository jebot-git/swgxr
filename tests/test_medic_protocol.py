import unittest
from server.medic_protocol import command,pose
class MedicProtocolTests(unittest.TestCase):
 def test_diagnose_excluded(self):
  with self.assertRaises(ValueError):command('heal',dict(request_id='medic-test',item_id='1',target_id='2',ability='diagnose'))
 def test_heal_requires_explicit_target(self):
  with self.assertRaises(ValueError):command('heal',dict(request_id='medic-test',item_id='1',ability='tenddamage'))
 def test_no_client_ham_or_range_authority(self):
  result=command('heal',dict(request_id='medic-test',item_id='1',target_id='2',ability='tenddamage',amount=999999,range_m=500))
  self.assertNotIn('amount',result);self.assertNotIn('range_m',result)
 def test_tracking_fail_closed(self):
  with self.assertRaises(ValueError):pose(dict(tracked=True,crossed=False,grips=True,left=[0,0,float('nan')],right=[0,0,0]))
 def test_release_without_tool(self):
  self.assertTrue(command('drag',dict(request_id='medic-test',target_id='2',release=True))['release'])
