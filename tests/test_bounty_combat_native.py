"""Compile actual BH implementation and native fire/impact/gesture branches with isolated engine dependencies."""
from pathlib import Path
import subprocess
import tempfile
import unittest
from tests.test_carbineer_native import method
ROOT=Path(__file__).resolve().parents[1]
NATIVE=ROOT/'vendor/Core3/MMOCoreORB/src/server/zone/objects/creature/commands'
class BountyCombatNative(unittest.TestCase):
 def test_actual_native_branches(self):
  live=(NATIVE/'SwgxrLiveCombat.h').read_text()
  with tempfile.TemporaryDirectory(prefix='swgxr-bounty-combat-') as directory:
   path=Path(directory)
   for name in ('Pistoleer','Carbineer','BountyHunter'):
    source=(ROOT/f'server/combat/Swgxr{name}.h').read_text()
    (path/f'{name.lower()}_native.inc').write_text(source[source.index(f'class Swgxr{name}'):].replace(' using Json=JSONSerializationType;', 'public:\n using Json=JSONSerializationType;',1))
   body=method(live,'  if(verb=="bountyhunter"){')+'\n'+method(live,'  if(verb=="fire"){')
   impact=live[live.index('  if(verb!="impact")'):live.index('\n }\npublic:',live.index('  if(verb!="impact")'))]
   structs=live[live.index(' struct Shot {'):live.index(' static double now()')]
   methods='\n'.join(method(live,x) for x in (' static std::string id(', ' static Json vector(', ' static Json position(', ' static double distance(', ' static bool key('))
   (path/'bountyhunter_fire.inc').write_text('class NativeFireHarness { public: using Json=JSONSerializationType;\n'+structs+methods+'\n static Json actor(CreatureObject*,CreatureObject* a,Session&){return {{"health",a->getHAM(0)},{"ham",Json::array({a->getHAM(0),a->getHAM(3),a->getHAM(6)})}};}\n static std::string id(Weapon* w){return w?std::to_string(w->getObjectID()):"";}\n static Json fire(CreatureObject* c,Session& s,const Json& request,double stamp){auto verb=request.at("action").get<std::string>();auto shotID=request.at("shot_id").get<std::string>();Json result={{"success",true}};\n'+body+impact+'\n}\n};')
   result=subprocess.run(['c++','-std=c++17','-I'+directory,'-I'+str(ROOT),str(ROOT/'tests/bounty_combat_native.cpp'),'-o',str(path/'check')],capture_output=True,text=True,timeout=60)
   self.assertEqual(result.returncode,0,result.stderr)
   result=subprocess.run([str(path/'check'),str(ROOT/'tests/fixtures/bounty_projectiles.json')],capture_output=True,text=True,timeout=10)
   self.assertEqual(result.returncode,0,result.stdout+result.stderr);print(result.stdout.strip())

 def test_native_modifier_sources(self):
  source=(ROOT/'server/combat/SwgxrBountyHunterModifiers.h').read_text()
  with tempfile.TemporaryDirectory(prefix='swgxr-bounty-modifiers-') as directory:
   path=Path(directory);(path/'bounty_modifiers.inc').write_text(source[source.index('class SwgxrBountyHunterModifiers'):])
   result=subprocess.run(['c++','-std=c++17','-I'+directory,'-I'+str(ROOT),str(ROOT/'tests/bounty_modifiers_native.cpp'),'-o',str(path/'check')],capture_output=True,text=True,timeout=30)
   self.assertEqual(result.returncode,0,result.stderr)
   result=subprocess.run([str(path/'check')],capture_output=True,text=True,timeout=10)
   self.assertEqual(result.returncode,0,result.stdout+result.stderr);print(result.stdout.strip())
