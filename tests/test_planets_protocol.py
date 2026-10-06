"""Ground-zone fences and original planet-qualified tickets; no native simulation."""
import copy
import unittest
from server.planets import SUPPORTED_PLANETS, context
from server.services_protocol import command
from server.session_protocol import snapshot, logout_command
from server.multiplayer_sync import MultiplayerSync

class PlanetsTests(unittest.TestCase):
 def test_source_zone_and_destination_independent(self):
  base=dict(request_id='planet_test_123',terminal_id='123',destination_id='Theed Starport',zone='tatooine',destination_planet='naboo')
  out=command('travel_purchase',base)
  self.assertEqual(out['zone'],'tatooine');self.assertEqual(out['destination_planet'],'naboo')
  for invalid in ('mustafar','../naboo','Naboo','',None):
   with self.assertRaises(ValueError):command('travel_purchase',dict(base,destination_planet=invalid))
 def test_all_source_zones_and_conflict(self):
  self.assertEqual(len(SUPPORTED_PLANETS),10)
  for p in SUPPORTED_PLANETS:self.assertEqual(context(dict(zone=p,planet=p)),dict(zone=p,planet=p))
  with self.assertRaises(ValueError):context(dict(zone='naboo',planet='tatooine'))
  self.assertEqual(context({}),{})
 def test_saved_non_tatooine_location(self):
  for p in SUPPORTED_PLANETS:
   row={'character_id':'12','source_kind':'core3_session_status','location':{'zone':p}}
   self.assertEqual(snapshot(row,'12'),row)
   out=logout_command(dict(zone=p,position=[0,0,0],building_id='0',cell_index=0));self.assertEqual(out['zone'],p)
 def test_zone_change_flushes_tracking_and_shot_identity(self):
  hub=MultiplayerSync(lambda:100.)
  world={'source_kind':'core3_world','actors':[],'players':[]}
  first={'player':dict(position=[0,0,0],zone='tatooine',building_id='0',cell_index=0),'world':world}
  hub.publish('a','1','s',first,1)
  payload=dict(character_id='1',session_id='s',sequence=1,position=[0,0,0],zone='tatooine',tracking={})
  hub.sync('a',payload);hub.sessions['a']['shots']['old']={}
  second=copy.deepcopy(first);second['player']['zone']='naboo';hub.publish('a','1','s',second,2)
  self.assertIsNone(hub.sessions['a']['pose']);self.assertEqual(hub.sessions['a']['shots'],{})
  with self.assertRaises(ValueError):hub.sync('a',dict(payload,sequence=2))
  reply=hub.sync('a',dict(payload,sequence=2,zone='naboo'));self.assertEqual(reply['zone'],'naboo')
