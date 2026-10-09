"""Exercise actual native support/group policy with isolated Core3 dependencies."""
from pathlib import Path
import subprocess
import tempfile
import unittest
import sys
ROOT=Path(__file__).resolve().parents[1]
class SquadLeaderNative(unittest.TestCase):
 def test_production_support(self):
  source=(ROOT/'server/combat/SwgxrSquadLeader.h').read_text()
  with tempfile.TemporaryDirectory(prefix='swgxr-squadleader-') as directory:
   path=Path(directory);(path/'squadleader_native.inc').write_text(source[source.index('class SwgxrSquadLeader'):])
   build=subprocess.run(['c++','-std=c++17','-I'+directory,'-I'+str(ROOT),str(ROOT/'tests/squadleader_native.cpp'),'-o',str(path/'check')],capture_output=True,text=True,timeout=60)
   self.assertEqual(build.returncode,0,build.stderr)
   run=subprocess.run([str(path/'check')],capture_output=True,text=True,timeout=15)
   self.assertEqual(run.returncode,0,run.stdout+run.stderr);print(run.stdout.strip())
 def test_original_grants_and_native_consumers(self):
  sys.path.insert(0,str(ROOT/'tools/assets'))
  from server.character_protocol import assets
  from character_formats import datatable
  rows={r['NAME']:r for r in datatable(assets().read('datatables/skill/skills.iff'))}
  for branch,grant in [('offense_01','steadyaim'),('defense_01','formup'),('defense_04','boostmorale'),('support_01','rally'),('support_03','retreat'),('offense_03','volleyFire')]:
   self.assertIn(grant,rows['outdoors_squadleader_'+branch]['COMMANDS'].split(','))
  native=ROOT/'vendor/Core3/MMOCoreORB/src/server/zone'
  for name in ('SquadLeaderPolicy.h','SwgxrSquadLeader.h','CoreCuCombat.h','CoreCuLoadoutPolicy.h'):
   self.assertEqual((ROOT/'server/combat'/name).read_bytes(),(native/'objects/creature/commands'/name).read_bytes())
  self.assertIn('SwgxrSquadLeader::regenerationScale(asCreatureObject(),attribute)',(native/'objects/creature/CreatureObjectImplementation.cpp').read_text())
  self.assertIn('SwgxrSquadLeader::statusRating(c,',(ROOT/'server/combat/CoreCuCombat.h').read_text())
  movement=(ROOT/'server/movement/SwgxrMovement.h').read_text()
  self.assertEqual(movement.count('SwgxrSquadLeader::movementScale(c)'),4)
  group=(native/'objects/group/GroupObjectImplementation.cpp').read_text()
  self.assertNotIn('new SquadLeaderBuff(',group)
  self.assertEqual(group.count('SwgxrSquadLeader::leave('),2)
