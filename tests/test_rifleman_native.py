"""Exercise production Rifleman class and whole native fire/impact/gesture branches."""
from pathlib import Path
import subprocess
import tempfile
import unittest
from tests.test_pistoleer_native import method
ROOT=Path(__file__).resolve().parents[1]
NATIVE=ROOT/'vendor/Core3/MMOCoreORB/src/server/zone/objects/creature/commands'

class RiflemanNative(unittest.TestCase):
 def test_native_execution(self):
  live=(NATIVE/'SwgxrLiveCombat.h').read_text()
  with tempfile.TemporaryDirectory(prefix='swgxr-rifleman-') as directory:
   path=Path(directory)
   for name in ('Pistoleer','Rifleman'):
    source=(ROOT/f'server/combat/Swgxr{name}.h').read_text()
    (path/f'{name.lower()}_native.inc').write_text(source[source.index(f'class Swgxr{name}'):].replace(' using Json=JSONSerializationType;', 'public:\n using Json=JSONSerializationType;',1))
   (path/'rifleman_target.inc').write_text('static Json rifleAvailability(CreatureObject* observer,AiAgent* ai){Json out=Json::object();'+live[live.index('for(auto ability:{"lethal_shot"'):live.index('out["melee_control_available"]',live.index('for(auto ability:{"lethal_shot"'))]+'return out;}')
   body=method(live,'  if(verb=="rifleman"){')+'\n'+method(live,'  if(verb=="fire"){')
   impact=live[live.index('  if(verb!="impact")'):live.index('\n }\npublic:',live.index('  if(verb!="impact")'))]
   structs=live[live.index(' struct Shot {'):live.index(' static double now()')]
   methods='\n'.join(method(live,x) for x in (' static std::string id(', ' static Json vector(', ' static Json position(', ' static double distance(', ' static bool key('))
   source=(ROOT/'server/smuggler/SwgxrSmuggler.h').read_text()
   (path/'confirmed_projectile.inc').write_text(method(source,'class SwgxrConfirmedProjectileCommand')+';')
   (path/'rifleman_fire.inc').write_text('class NativeFireHarness { public: using Json=JSONSerializationType;\n'+structs+methods+'\n static Json actor(CreatureObject*,CreatureObject* a,Session&){return {{"health",a->getHAM(0)},{"ham",Json::array({a->getHAM(0),a->getHAM(3),a->getHAM(6)})}};}\n static std::string id(Weapon* w){return w?std::to_string(w->getObjectID()):"";}\n static Json fire(CreatureObject* c,Session& s,const Json& request,double stamp){auto verb=request.at("action").get<std::string>();auto shotID=request.at("shot_id").get<std::string>();Json result={{"success",true}};\n'+body+impact+'\n}\n};')
   r=subprocess.run(['c++','-std=c++17','-I'+directory,'-I'+str(ROOT),str(ROOT/'tests/rifleman_native.cpp'),'-o',str(path/'check')],capture_output=True,text=True,timeout=60)
   self.assertEqual(r.returncode,0,r.stderr)
   r=subprocess.run([str(path/'check')],capture_output=True,text=True,timeout=10)
   self.assertEqual(r.returncode,0,r.stdout+r.stderr);print(r.stdout.strip())

 def test_policy(self):
  with tempfile.TemporaryDirectory(prefix='swgxr-rifleman-policy-') as directory:
   binary=Path(directory)/'check'
   r=subprocess.run(['c++','-std=c++17','-I'+str(ROOT),str(ROOT/'tests/rifleman_policy.cpp'),'-o',str(binary)],capture_output=True,text=True,timeout=30)
   self.assertEqual(r.returncode,0,r.stderr)
   r=subprocess.run([str(binary)],capture_output=True,text=True,timeout=10)
   self.assertEqual(r.returncode,0,r.stdout+r.stderr);print(r.stdout.strip())
