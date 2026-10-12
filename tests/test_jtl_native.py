"""Execute actual native grant methods and authoritative flight/placement budgets."""
from pathlib import Path
import subprocess
import tempfile
import unittest
from tests.test_carbineer_native import method
ROOT=Path(__file__).resolve().parents[1]
class JtlNative(unittest.TestCase):
 def compile_run(self,source,include=None,include_name='jtl_provision_native.inc'):
  with tempfile.TemporaryDirectory(prefix='swgxr-jtl-') as temp:
   temp=Path(temp)
   if include:(temp/include_name).write_text(include)
   result=subprocess.run(['c++','-std=c++14','-I'+str(ROOT),'-I'+str(temp),str(ROOT/'tests'/source),'-o',str(temp/'test')],capture_output=True,text=True,timeout=60)
   self.assertEqual(result.returncode,0,result.stderr)
   result=subprocess.run([str(temp/'test')],capture_output=True,text=True,timeout=10)
   self.assertEqual(result.returncode,0,result.stdout+result.stderr)
   print(result.stdout.strip())
 def test_flight_collision(self):self.compile_run('jtl_flight_collision.cpp')
 def test_flight_policy(self):self.compile_run('jtl_policy.cpp')
 def test_ground_building_never_indexes_ship_cells(self):
  source=(ROOT/'server/jtl/SwgxrJtl.h').read_text()
  self.compile_run('jtl_cell_native.cpp','class NativeJtl {public: static ShipObject* current(CreatureObject*c){return c->ship;}\n'+method(source,' static CellObject* playerCell(')+'\n};','jtl_cell_native.inc')
 def test_doorway_segment_keeps_both_room_wall_checks(self):
  source=(ROOT/'server/jtl/SwgxrJtl.h').read_text()
  self.compile_run('jtl_walk_native.cpp','class NativeJtl {public:\n'+method(source,' static bool walkClear(')+'\n};','jtl_walk_native.inc')
 def test_actual_provision(self):
  source=(ROOT/'server/jtl/SwgxrJtl.h').read_text()
  methods='\n'.join(method(source,signature) for signature in (' static bool yacht(', ' static ShipObject* entitled(', ' static void persist(', ' static void provision('))
  self.compile_run('jtl_provision_native.cpp','class NativeJtlProvision { public: static bool enabled(){return feature;}\n'+methods+'\n};')
 def test_actual_space_snapshot_and_logout_replay(self):
  native=ROOT/'vendor/Core3/MMOCoreORB/src/server/zone/objects/creature/commands'
  services=(native/'SwgxrServices.h').read_text();live=(native/'SwgxrLiveCombat.h').read_text()
  session=method(services,' static Json sessionState(')
  branch=method(live,'  if(SwgxrJtl::aboard(c)){')
  helpers='static Json location(CreatureObject*c){return {{"zone",std::string(c->zone.name)},{"position",c->position},{"building_id","0"},{"cell_index",0},{"heading_radians",c->direction.value}};} static void move(CreatureObject*c,const Json&r){SwgxrPlanets::require(c,r);c->position=r.at("position");++c->moves;}'
  include='class NativeServices {public:'+helpers+session+'};\nclass NativeLive {public:'+method(live,' static Json ham(')+' static Json snapshot(CreatureObject*c,Session&session){'+branch+'throw std::runtime_error("ground");}};'
  self.compile_run('jtl_session_native.cpp',include,'jtl_session_native.inc')
 def test_original_cell_index_and_furnishing_integration(self):
  source=(ROOT/'server/jtl/SwgxrJtl.h').read_text()
  self.assertIn('pob->getCell(index-1)',source)
  self.assertIn('SwgxrHousing::furnish(c,request,recover,true)',source)
  self.assertIn('getMaximumNumberOfPlayerItems()',source)
  self.assertIn('terminal->handleObjectMenuSelect(c,cmd=="elevator_up"?198:199)',source)
  self.assertEqual(source,(ROOT/'vendor/Core3/MMOCoreORB/src/server/zone/objects/creature/commands/SwgxrJtl.h').read_text())
if __name__=='__main__':unittest.main()
