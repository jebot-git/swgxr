import unittest
from server.scout_protocol import command,snapshot

class RangerProtocolTests(unittest.TestCase):
 def request(self,**kw):return dict(position=[3527,5,-4810],zone='tatooine',request_id='ranger_test123',**kw)
 def test_status_and_cell(self):
  self.assertEqual(command('ranger_status',dict(position=[0,0,0],zone='naboo',building_id='123',cell_index=2))['cell_index'],2)
  for args in [dict(building_id='0',cell_index=2),dict(building_id='１２',cell_index=1),dict(building_id='123',cell_index=True)]:
   with self.assertRaises(ValueError):command('ranger_status',self.request(**args))
 def test_owned_ascii_id(self):
  self.assertEqual(command('conceal',self.request(item_id='99'))['item_id'],'99')
  for v in ('１２','',None,'-1','18446744073709551616'):
   with self.assertRaises(ValueError):command('conceal',self.request(item_id=v))
 def test_physical_handover(self):
  self.assertEqual(command('conceal',self.request(item_id='99',target_id='12',hand_position=[3528,6.5,-4810]))['target_id'],'12')
  for h in (None,[3527,50,-4810],[float('nan'),5,-4810]):
   with self.assertRaises(ValueError):command('conceal',self.request(item_id='99',target_id='12',hand_position=h))
 def test_no_client_grants(self):
  q=command('conceal',self.request(item_id='99',power=100,duration=999,charges=50,force=True))
  self.assertFalse({'power','duration','charges','force'}&q.keys())
 def test_track_types_and_receipts(self):
  for kind in ('animal','npc','player'):self.assertEqual(command('area_track',self.request(track_type=kind))['track_type'],kind)
  with self.assertRaises(ValueError):command('area_track',self.request(track_type='all'))
  with self.assertRaises(ValueError):command('rescue',dict(position=[0,0,0],target_id='1'))
 def test_bounded_native_output(self):
  d=dict(source_kind='core3_scout',character_id='1',state=dict(character_id='1',ranger=dict(tracking=dict(results=[{}]*257))))
  with self.assertRaises(ValueError):snapshot(d,'1')
