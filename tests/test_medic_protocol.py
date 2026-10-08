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
 def test_bandage_requires_tracking_and_target_but_no_focus(self):
  tracked=dict(tracked=True,crossed=False,grips=False,left=[0,1,0],right=[0,1,0])
  out=command('bandage',dict(request_id='bandage-test',target_id='2',pose=tracked,amount=99999,ability='quickheal'))
  self.assertEqual(out['action'],'bandage');self.assertNotIn('item_id',out);self.assertNotIn('amount',out);self.assertNotIn('ability',out)
  with self.assertRaises(ValueError):command('bandage',dict(request_id='bandage-test',target_id='2'))

 def test_retired_wound_abilities_are_not_selectable(self):
  for name in ('healwound','tendwound','diagnose'):
   with self.assertRaises(ValueError):command('select',dict(request_id='medic-test',item_id='1',ability=name))
 def test_wound_pack_is_an_exact_item_action(self):
  data=dict(request_id='wound-pack-test',item_id='1',target_id='2',pose=dict(tracked=True,crossed=False,grips=False,left=[0,1,0],right=[0,1,0]),amount=100000,attribute=8)
  out=command('wound_pack',data)
  self.assertEqual(out['item_id'],'1');self.assertEqual(out['target_id'],'2');self.assertNotIn('amount',out);self.assertNotIn('attribute',out)
  for field in ('item_id','target_id','pose'):
   invalid=data.copy();invalid.pop(field)
   with self.assertRaises(ValueError):command('wound_pack',invalid)

 def test_medical_item_has_no_client_command_or_power_authority(self):
  data=dict(request_id='medical-item-test',item_id='1',target_id='2',pose=dict(tracked=True,crossed=False,grips=False,left=[0,1,0],right=[0,1,0]),command='reviveplayer',amount=999999,attribute=8)
  out=command('medical_item',data)
  self.assertEqual(set(out)-{'zone'}, {'action','request_id','item_id','target_id','pose'})
  for field in ('item_id','target_id','pose'):
   invalid=data.copy();invalid.pop(field)
   with self.assertRaises(ValueError):command('medical_item',invalid)
 def test_stim_is_an_item_not_focus_ability(self):
  with self.assertRaises(ValueError):command('select',dict(request_id='medical-item-test',item_id='1',ability='healdamage'))
