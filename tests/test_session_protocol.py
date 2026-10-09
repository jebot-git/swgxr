import unittest
from server.session_protocol import logout_command,snapshot
from server.vehicles_protocol import command
class SessionProtocol(unittest.TestCase):
 def test_logout_requires_actual_complete_source_cell(self):
  value=dict(position=[3500,5,-4800],building_id='0',cell_index=0,heading_radians=.5)
  self.assertEqual(logout_command(value),dict(value,action='logout'))
  for update in ({'position':[float('nan'),0,0]},{'position':[9000,0,0]},{'building_id':'12'},{'cell_index':1},{'heading_radians':True}):
   with self.assertRaises(ValueError):logout_command(dict(value,**update))
 def test_native_location_ownership(self):
  row={'source_kind':'core3_session_logout','character_id':'1','saved':True,'location':{'zone':'tatooine'}}
  self.assertEqual(snapshot(row,'1'),row)
  with self.assertRaises(ValueError):snapshot(row,'2')
 def test_space_logout_is_bounded_recovery_intent_not_ground_motion(self):
  value=dict(zone='space_tatooine',position=[0,.4,20],building_id='42',cell_index=1,request_id='logout_ship_01')
  self.assertEqual(logout_command(value)['zone'],'space_tatooine')
  self.assertEqual(logout_command(dict(value,building_id='0',cell_index=0))['cell_index'],0)
  for changes in ({'position':[0,65,0]},{'cell_index':0},{'cell_index':12},{'building_id':'0'},{'zone':'space_yavin4'}):
   with self.assertRaises(ValueError):logout_command(dict(value,**changes))
 def test_all_vehicle_actions_preserve_source_pose(self):
  for action,extra in [('status',{}),('call',{'device_id':'123'}),('dismount',{})]:
   q=command(action,dict(extra,position=[3500,5,-4800],building_id='0',cell_index=0))
   self.assertEqual(q['position'],[3500,5,-4800]);self.assertEqual(q['cell_index'],0)
