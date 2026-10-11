import subprocess
import tempfile
import unittest
from pathlib import Path
from server import jtl_protocol as protocol
from tests.test_carbineer_native import method
ROOT=Path(__file__).resolve().parents[1]
class TargetingTests(unittest.TestCase):
 def test_protocol_selection_and_components(self):
  req={'request_id':'target-test-001','target_id':'234'}
  self.assertEqual(protocol.command('target',req)['target_id'],'234')
  self.assertEqual(protocol.command('target',dict(req,target_id='0'))['target_id'],'0')
  for slot in (-1,0,1,111):self.assertEqual(protocol.command('subsystem',dict(req,component_slot=slot))['component_slot'],slot)
  for slot in (True,-2,112,'1'):
   with self.assertRaises(ValueError):protocol.command('subsystem',dict(req,component_slot=slot))
  for slot in (11,20,False):
   with self.assertRaises(ValueError):protocol.command('missile_select',dict(req,weapon_slot=slot))
  out=protocol.command('missile_fire',dict(req,weapon_slot=12,component_slot=1,damage=999,acquired=True))
  self.assertEqual(set(out),{'action','request_id','target_id','weapon_slot','component_slot'})
  with self.assertRaises(ValueError):protocol.command('missile_fire',dict(req,weapon_slot=12))
 def test_ammunition_protocol(self):
  from server.services_protocol import command
  payload={'request_id':'ammo-test-001','terminal_id':'10','ship_id':'20','component_id':'30','slot':13}
  self.assertEqual(command('ship_ammo_load',payload)['component_id'],'30')
  for key in ('ship_id','component_id','slot'):
   with self.assertRaises(ValueError):command('ship_ammo_load',{k:v for k,v in payload.items() if k!=key})
 def test_native_policy_and_per_victim_subsystem(self):
  with tempfile.TemporaryDirectory() as tmp:
   exe=Path(tmp)/'test'
   subprocess.run(['c++','-std=c++14','-I'+str(ROOT),str(ROOT/'tests/jtl_targeting_policy.cpp'),'-o',str(exe)],check=True)
   subprocess.run([str(exe)],check=True)
   source=(ROOT/'vendor/Core3/MMOCoreORB/src/server/zone/managers/spacecombat/projectile/ShipProjectile.h').read_text()
   methods=method(source,'uint8 getComponentSlotForTarget(')+method(source,'\tvoid setComponentTargetID(')
   code='#include <cstdint>\n#include <cassert>\nusing uint8=uint8_t;using uint64=uint64_t;struct Shot {uint8 componentSlot=1;uint64 componentTargetID=0;bool scopedComponent=false;'+methods+'};int main(){Shot s;s.setComponentTargetID(123);assert(s.getComponentSlotForTarget(123)==1);assert(s.getComponentSlotForTarget(456)==255);s.componentSlot=255;assert(s.getComponentSlotForTarget(123)==255);s.componentSlot=0;assert(s.getComponentSlotForTarget(123)==0);}'
   cpp=Path(tmp)/'shot.cpp';cpp.write_text(code)
   subprocess.run(['c++','-std=c++14',str(cpp),'-o',str(exe)],check=True);subprocess.run([str(exe)],check=True)
