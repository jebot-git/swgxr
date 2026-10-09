"""Compile actual grenade lifecycle/area selection with isolated Core3 dependencies."""
from pathlib import Path
import subprocess
import tempfile
import unittest
from tests.test_pistoleer_native import method
ROOT=Path(__file__).resolve().parents[1]

class CommandoGrenadesNative(unittest.TestCase):
 def test_native_lifecycle(self):
  source=(ROOT/'server/scout/SwgxrGrenade.h').read_text()
  with tempfile.TemporaryDirectory(prefix='swgxr-grenades-') as directory:
   path=Path(directory)
   body=source[source.index('class SwgxrGrenadeStrike'):]
   body=body.replace(method(body,' static long long now('),' static long long now(){return testNow;}')
   (path/'grenade.inc').write_text(body)
   movement=(ROOT/'server/movement/SwgxrMovement.h').read_text()
   (path/'controls.inc').write_text('class MovementHarness {public: using Json=JSONSerializationType;'+method(movement,' static Json controls(')+'};')
   scout=(ROOT/'server/scout/SwgxrScout.h').read_text()
   (path/'scout.inc').write_text('class ScoutTargetsHarness {public:'+method(scout,' static void targetObjects(')+'};')
   compiled=subprocess.run(['c++','-std=c++17','-I'+directory,'-I'+str(ROOT),'-I'+str(ROOT/'server/combat'),str(ROOT/'tests/commando_grenades_native.cpp'),'-o',str(path/'test')],capture_output=True,text=True,timeout=60)
   self.assertEqual(compiled.returncode,0,compiled.stderr)
   run=subprocess.run([str(path/'test')],capture_output=True,text=True,timeout=15)
   self.assertEqual(run.returncode,0,run.stdout+run.stderr)
   print(run.stdout.strip())
 def test_native_mirrors_and_routing(self):
  native=ROOT/'vendor/Core3/MMOCoreORB/src/server/zone/objects/creature/commands'
  for name in ('GrenadePolicy.h','SwgxrGrenade.h','SwgxrScout.h'):
   self.assertEqual((ROOT/'server/scout'/name).read_bytes(),(native/name).read_bytes())
  self.assertEqual((ROOT/'server/movement/SwgxrMovement.h').read_bytes(),(native/'SwgxrMovement.h').read_bytes())
  scout=(native/'SwgxrScout.h').read_text()
  self.assertIn('SwgxrGrenade::accept',scout)
  self.assertIn('entry["grenade_eligible"]=grenadeEligible',scout)
  self.assertIn('command(c,"throwtrap"',scout)
  inventory=(native/'SwgxrInventory.h').read_text()
  self.assertIn('result["grenade_available"]',inventory)
  ai=(ROOT/'vendor/Core3/MMOCoreORB/src/server/zone/objects/creature/ai/AiAgentImplementation.cpp').read_text()
  self.assertIn('getSkillMod("private_commando_glop")',ai)
