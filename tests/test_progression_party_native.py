"""Execute production progression wrappers with isolated Core3 dependencies."""
from pathlib import Path
import subprocess
import tempfile
import unittest
ROOT = Path(__file__).resolve().parents[1]
class ProgressionPartyNative(unittest.TestCase):
 def test_production_wrappers(self):
  with tempfile.TemporaryDirectory(prefix='swgxr-progression-') as d:
   directory=Path(d)
   for name,source,start in [('forget_native.inc','server/progression/SwgxrSkillForgetting.h','class SwgxrSkillForgetting'),('leadership_native.inc','server/progression/SwgxrLeadershipExperience.h','class SwgxrLeadershipExperience'),('party_policy.inc','server/party/SwgxrPartyPolicy.h','class SwgxrPartyPolicy')]:
    text=(ROOT/source).read_text();directory.joinpath(name).write_text(text[text.index(start):].replace('#endif',''))
   build=subprocess.run(['c++','-std=c++17','-Wall','-Wextra','-I'+str(ROOT),'-I'+d,str(ROOT/'tests/progression_party_native.cpp'),'-o',str(directory/'check')],capture_output=True,text=True,timeout=60)
   self.assertEqual(build.returncode,0,build.stderr)
   result=subprocess.run([str(directory/'check')],capture_output=True,text=True,timeout=15)
   self.assertEqual(result.returncode,0,result.stdout+result.stderr);print(result.stdout.strip())
 def test_production_party_formation(self):
  with tempfile.TemporaryDirectory(prefix='swgxr-party-form-') as d:
   directory=Path(d)
   for name,source,start in [('party_formation.inc','server/party/SwgxrParty.h','class SwgxrParty {'),('party_policy.inc','server/party/SwgxrPartyPolicy.h','class SwgxrPartyPolicy')]:
    text=(ROOT/source).read_text();directory.joinpath(name).write_text(text[text.index(start):].replace('#endif',''))
   build=subprocess.run(['c++','-std=c++17','-I'+str(ROOT),'-I'+d,str(ROOT/'tests/party_formation_native.cpp'),'-o',str(directory/'check')],capture_output=True,text=True,timeout=60)
   self.assertEqual(build.returncode,0,build.stderr)
   result=subprocess.run([str(directory/'check')],capture_output=True,text=True,timeout=15)
   self.assertEqual(result.returncode,0,result.stdout+result.stderr);print(result.stdout.strip())
 def test_mirrors_and_native_integration(self):
  native=ROOT/'vendor/Core3/MMOCoreORB/src/server/zone'
  for name in ('SwgxrSkillForgetting.h','LeadershipExperiencePolicy.h','SwgxrLeadershipExperience.h'):
   self.assertEqual((ROOT/'server/progression'/name).read_bytes(),(native/'objects/creature/commands'/name).read_bytes())
  source=(native/'managers/player/PlayerManagerImplementation.cpp').read_text();award=source[source.index('int PlayerManagerImplementation::awardExperience('):source.index('void PlayerManagerImplementation::sendLoginMessage(')]
  self.assertEqual(award.count('SwgxrLeadershipExperience::earned(player, xpType, xp);'),1)
  self.assertLess(award.index('playerObject->addExperience('),award.index('SwgxrLeadershipExperience::earned('))
  surrender=(native/'managers/skill/SkillManager.cpp').read_text();self.assertIn('ghost->addSkillPoints(skill->getSkillPointsRequired());',surrender)
  for path in (ROOT/'server/services/SwgxrServices.h',native/'objects/creature/commands/SwgxrServices.h'):
   service=path.read_text();self.assertIn('out["forget_skills"]=SwgxrSkillForgetting::snapshot(c)',service);self.assertIn('else if(action=="skill_forget")',service)
if __name__=='__main__': unittest.main()
