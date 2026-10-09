"""Compile actual Volley Fire native authority with isolated Core3 dependencies."""
from pathlib import Path
import subprocess
import tempfile
import unittest
from tests.test_pistoleer_native import method
ROOT=Path(__file__).resolve().parents[1]
NATIVE=ROOT/'vendor/Core3/MMOCoreORB/src/server/zone/objects/creature/commands'
class VolleyFireNative(unittest.TestCase):
 def test_production_ledger_and_launch(self):
  source=(ROOT/'server/combat/SwgxrVolleyFire.h').read_text();body=source[source.index('class SwgxrVolleyFire'):]
  body=body.replace(method(body,' static long long millis('),' static long long millis(){return testNow;}')
  with tempfile.TemporaryDirectory(prefix='swgxr-volley-') as directory:
   path=Path(directory);(path/'volley_native.inc').write_text(body)
   (path/'volley_route.inc').write_text(method((NATIVE/'SwgxrLiveCombat.h').read_text(),' static Json volleyAction('))
   geometry=[]
   for name in ('Tka','Swordsman','Pikeman','Fencer'):
    source=(ROOT/'server/combat'/('Swgxr'+name+'.h')).read_text()
    geometry.append('class '+name+'Geometry {public:'+method(source,' static bool eligible(')+'};')
   (path/'volley_geometry.inc').write_text('\n'.join(geometry))
   build=subprocess.run(['c++','-std=c++17','-pthread','-I'+directory,'-I'+str(ROOT),str(ROOT/'tests/volley_fire_native.cpp'),'-o',str(path/'check')],capture_output=True,text=True,timeout=60)
   self.assertEqual(build.returncode,0,build.stderr)
   run=subprocess.run([str(path/'check')],capture_output=True,text=True,timeout=15)
   self.assertEqual(run.returncode,0,run.stdout+run.stderr);print(run.stdout.strip())
 def test_native_guarantee_and_group_hooks(self):
  for name in ('SwgxrVolleyFire.h','VolleyFirePolicy.h'):
   self.assertEqual((ROOT/'server/combat'/name).read_bytes(),(NATIVE/name).read_bytes())
  combat=(ROOT/'vendor/Core3/MMOCoreORB/src/server/zone/managers/combat/CombatManager.cpp').read_text()
  self.assertIn('corecu::volley::claimHit(attacker->getObjectID(),creoDefender->getObjectID())',combat)
  self.assertEqual(combat.count('damage*=SwgxrSquadLeader::outputDamageScale'),3)
  group=(ROOT/'vendor/Core3/MMOCoreORB/src/server/zone/objects/group/GroupObjectImplementation.cpp').read_text()
  self.assertEqual(group.count('corecu::volley::leave('),2)
  cast=method((NATIVE/'SwgxrLiveCombat.h').read_text(),'  if(verb=="squadleader"){')
  self.assertIn('stamp-it->second.time>8',cast)
  self.assertIn('s.shots.size()>=128',cast)
  for name in ('VolleyFireCommand.h','VolleyFireAttackCommand.h'):
   self.assertIn('never queue free legacy attacks', (NATIVE/name).read_text())
