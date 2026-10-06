import copy, math, unittest
from unittest.mock import patch
from server.services_protocol import command, snapshot
class VendorPlacementTests(unittest.TestCase):
 def setUp(self):
  self.body={'vendor_id':'123','request_id':'vendor-test-123','position':[1,2,3],'building_id':'456','cell_index':2,'placement_position':[2,2,3],'placement_heading':1.5}
 def test_valid_native_pose_and_no_terminal_dependency(self):
  result=command('vendor_place',dict(self.body,terminal_id='987'))
  self.assertEqual(result['placement_position'],self.body['placement_position']);self.assertNotIn('terminal_id',result)
 def test_required_fields(self):
  for key in self.body:
   body=dict(self.body);body.pop(key)
   with self.subTest(key=key),self.assertRaises(ValueError):command('vendor_place',body)
 def test_reject_invalid_pose_before_native_mutation(self):
  for point in [None,[],[0,0],[True,0,0],[0,float('nan'),0],[0,2049,0],[8193,0,0],'0,0,0']:
   with self.subTest(point=point),self.assertRaises(ValueError):command('vendor_place',dict(self.body,placement_position=point))
  for angle in [None,True,'1',float('inf'),float('nan'),7]:
   with self.subTest(angle=angle),self.assertRaises(ValueError):command('vendor_place',dict(self.body,placement_heading=angle))
 def test_outdoors_and_invalid_identity_rejected(self):
  for fields in [{'building_id':'0','cell_index':0},{'cell_index':0},{'vendor_id':'0'},{'vendor_id':'-1'},{'vendor_id':str(2**64)},{'request_id':'x'}]:
   with self.subTest(fields=fields),self.assertRaises(ValueError):command('vendor_place',dict(self.body,**fields))
 def test_projection_retains_native_identity_and_does_not_mutate_input(self):
  raw={'source_kind':'core3_services','character_id':'11','vendors':[{'id':'12','client_crc':0,'template':'object/tangible/vendor/vendor_terminal_bulky.iff','custom_name':'Vendor: Test','customization_hex':''}],'placed_vendors':[]}
  original=copy.deepcopy(raw)
  with patch('server.services_protocol.template_names',return_value={}):result=snapshot(raw,'11')['state']['vendors'][0]
  self.assertEqual(result['id'],'12');self.assertEqual(result['name'],'Vendor: Test');self.assertFalse(result['deletable']);self.assertEqual(result['category'],'vendors');self.assertEqual(raw,original)
  with self.assertRaises(ValueError):snapshot(raw,'99')
 def test_bounds(self):
  with self.assertRaises(ValueError):snapshot({'source_kind':'core3_services','character_id':'11','vendors':[{}]*65},'11')
if __name__=='__main__':unittest.main()
