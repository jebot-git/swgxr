"""Execute production bounty objective, dispatch and search logic with isolated engine dependencies."""
from pathlib import Path
import subprocess
import tempfile
import unittest
from tests.test_pistoleer_native import method
ROOT=Path(__file__).resolve().parents[1]
ZONE=ROOT/'vendor/Core3/MMOCoreORB/src/server/zone'
class BountyNative(unittest.TestCase):
 def test_production_lifecycle(self):
  objective=(ZONE/'objects/mission/BountyMissionObjectiveImplementation.cpp').read_text()
  names=['activate','deactivate','abort','complete','updateMissionStatus','swgxrState','swgxrDroidReport','cancelAllTasks','handleNpcTargetKilled']
  with tempfile.TemporaryDirectory(prefix='swgxr-bounty-') as d:
   path=Path(d)
   bodies=[]
   for name in names:
    prefix=('String' if name=='swgxrState' else 'void')+' BountyMissionObjectiveImplementation::'+name+'('
    bodies.append(method(objective,prefix).replace('BountyMissionObjectiveImplementation::',''))
   (path/'bounty_objective.inc').write_text('\n'.join(bodies))
   task=(ZONE/'objects/mission/bountyhunter/events/FindTargetTask.h').read_text()
   (path/'bounty_search.inc').write_text('\n'.join(method(task,p) for p in ['\tbool findAndTrackSuccess(', '\tbool getSuccess(', '\tint calculateTime(']))
   dispatch=(ZONE/'objects/mission/bountyhunter/BountyHunterDroid.cpp').read_text()
   (path/'bounty_dispatch.inc').write_text('\n'.join(method(dispatch,prefix).replace('BountyHunterDroid::','') for prefix in ('Reference<Task*> BountyHunterDroid::performAction(', 'Reference<CallArakydTask*> BountyHunterDroid::callArakydDroid(', 'Reference<FindTargetTask*> BountyHunterDroid::findTarget(', 'Reference<FindTargetTask*> BountyHunterDroid::transmitBiologicalSignature(')))
   (path/'bounty_runner.inc').write_text(method(task,'\tvoid run()'))
   target=(ZONE/'objects/mission/bountyhunter/events/BountyHunterTargetTask.h').read_text()
   (path/'bounty_target.inc').write_text(method(target,'\tvoid run()'))
   delivery=(ZONE/'objects/mission/bountyhunter/events/CallArakydTask.h').read_text()
   (path/'bounty_delivery.inc').write_text(method(delivery,'\tvoid run()'))
   build=subprocess.run(['c++','-std=c++17','-I'+d,str(ROOT/'tests/bounty_native.cpp'),'-o',str(path/'check')],capture_output=True,text=True,timeout=60)
   self.assertEqual(build.returncode,0,build.stderr)
   run=subprocess.run([str(path/'check')],capture_output=True,text=True,timeout=15)
   self.assertEqual(run.returncode,0,run.stdout+run.stderr);print(run.stdout.strip())
 def test_native_integration_contract(self):
  self.assertEqual((ROOT/'server/bounty/SwgxrBounty.h').read_bytes(),(ZONE/'objects/creature/commands/SwgxrBounty.h').read_bytes())
  manager=(ZONE/'managers/mission/MissionManagerImplementation.cpp').read_text()
  self.assertNotIn('getPotentialPlayerBountyTargets',method(manager,'void MissionManagerImplementation::randomizeBountyTerminalMissions('))
  accept=method(manager,'void MissionManagerImplementation::handleMissionAccept(')
  self.assertIn('mission->getTargetObjectId() != 0',accept)
  self.assertIn('hasBountyMission',accept)
  task=(ZONE/'objects/mission/bountyhunter/events/FindTargetTask.h').read_text()
  self.assertIn('return state == Completed;',task)
  self.assertIn('objective->getPlayerOwner() != player',task)
  target=(ZONE/'objects/mission/bountyhunter/events/BountyHunterTargetTask.h').read_text()
  self.assertEqual(target.count('if (randomStarport == nullptr)'),2)
  self.assertIn('strongMissionRef->setEndPosition(currentPosition.getX()',target)
  self.assertIn('objectiveRef->getObjectiveStatus() != BountyMissionObjective::INITSTATUS',target)
  call=(ZONE/'objects/mission/bountyhunter/events/CallArakydTask.h').read_text()
  self.assertIn('1 /* TRANSMITBIOLOGICALSIGNATURE */',call)
  self.assertIn('objectiveRef->getPlayerOwner() != playerRef',call)
