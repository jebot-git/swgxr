"""Run actual Carbineer methods, control policy, and native request/impact branches."""
from pathlib import Path
import subprocess
import tempfile
import unittest
ROOT=Path(__file__).resolve().parents[1]
NATIVE=ROOT/'vendor/Core3/MMOCoreORB/src/server/zone/objects/creature/commands'

def method(source, signature):
 start=source.index(signature);at=source.index('{',start);depth=1;end=at+1
 while depth:
  depth+=(source[end]=='{')-(source[end]=='}');end+=1
 return source[start:end]

class CarbineerNative(unittest.TestCase):
 def test_native_carbineer(self):
  source=(ROOT/'server/combat/SwgxrPistoleer.h').read_text()
  live=(NATIVE/'SwgxrLiveCombat.h').read_text()
  with tempfile.TemporaryDirectory(prefix='swgxr-carbineer-') as directory:
   path=Path(directory)
   (path/'pistoleer_native.inc').write_text(source[source.index('class SwgxrPistoleer'):].replace(' using Json=JSONSerializationType;', 'public:\n using Json=JSONSerializationType;',1))
   body=method(live,'  if(verb=="carbineer"){')+'\n'+method(live,'  if(verb=="fire"){')
   impact=live[live.index('  if(verb!="impact")'):live.index('\n }\npublic:',live.index('  if(verb!="impact")'))]
   structs=live[live.index(' struct Shot {'):live.index(' static double now()')]
   methods='\n'.join(method(live,x) for x in (' static std::string id(', ' static Json vector(', ' static Json position(', ' static double distance(', ' static bool key('))
   (path/'carbineer_native.inc').write_text(('class SwgxrCarbineer'+(ROOT/'server/combat/SwgxrCarbineer.h').read_text().split('class SwgxrCarbineer',1)[1]).replace(' using Json=JSONSerializationType;', 'public:\n using Json=JSONSerializationType;',1))
   (path/'carbineer_fire.inc').write_text('class NativeFireHarness { public: using Json=JSONSerializationType;\n'+structs+methods+'\n static Json actor(CreatureObject*,CreatureObject* a,Session&){return {{"health",a->getHAM(0)},{"ham",Json::array({a->getHAM(0),a->getHAM(3),a->getHAM(6)})}};}\n static std::string id(Weapon* w){return w?std::to_string(w->getObjectID()):"";}\n static Json fire(CreatureObject* c,Session& s,const Json& request,double stamp){auto verb=request.at("action").get<std::string>();auto shotID=request.at("shot_id").get<std::string>();Json result={{"success",true}};\n'+body+impact+'\n}\n};')
   r=subprocess.run(['c++','-std=c++17','-I'+directory,'-I'+str(ROOT),str(ROOT/'tests/carbineer_native.cpp'),'-o',str(path/'check')],capture_output=True,text=True,timeout=60)
   self.assertEqual(r.returncode,0,r.stderr)
   r=subprocess.run([str(path/'check')],capture_output=True,text=True,timeout=10)
   self.assertEqual(r.returncode,0,r.stdout+r.stderr);print(r.stdout.strip())

 def test_control_policy(self):
  with tempfile.TemporaryDirectory(prefix='swgxr-carbineer-policy-') as directory:
   binary=Path(directory)/'check'
   r=subprocess.run(['c++','-std=c++17','-I'+str(ROOT),str(ROOT/'tests/carbineer_policy.cpp'),'-o',str(binary)],capture_output=True,text=True,timeout=30)
   self.assertEqual(r.returncode,0,r.stderr)
   r=subprocess.run([str(binary)],capture_output=True,text=True,timeout=10)
   self.assertEqual(r.returncode,0,r.stdout+r.stderr);print(r.stdout.strip())
