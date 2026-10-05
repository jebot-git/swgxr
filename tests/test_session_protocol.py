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
 def test_all_vehicle_actions_preserve_source_pose(self):
  for action,extra in [('status',{}),('call',{'device_id':'123'}),('dismount',{})]:
   q=command(action,dict(extra,position=[3500,5,-4800],building_id='0',cell_index=0))
   self.assertEqual(q['position'],[3500,5,-4800]);self.assertEqual(q['cell_index'],0)
