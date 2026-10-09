"""Execute production CM command and DoT lifecycle code with bounded native dependencies."""
from pathlib import Path
import subprocess
import tempfile
import unittest
import re
from tests.test_pistoleer_native import method

ROOT=Path(__file__).resolve().parents[1]
NATIVE=ROOT/'vendor/Core3/MMOCoreORB/src/server/zone/objects'

class CombatMedicEffects(unittest.TestCase):
 def test_production_command_and_ticks(self):
  with tempfile.TemporaryDirectory(prefix='swgxr-cm-effects-') as directory:
   path=Path(directory)
   for source,name in [(ROOT/'server/medic/SwgxrCombatMedicEffects.h','cm_effects.inc'),(NATIVE/'creature/commands/DotPackCommand.h','cm_command.inc')]:
    text=source.read_text();text=re.sub(r'^#include[^\n]*\n','',text,flags=re.M);(path/name).write_text(text)
   header=(NATIVE/'creature/damageovertime/DamageOverTime.h').read_text()
   cpp=(NATIVE/'creature/damageovertime/DamageOverTime.cpp').read_text()
   (path/'cm_configure.inc').write_text(method(header,'    void configureCombatMedic('))
   names=['applyDot','initDot','doPoisonTick','doDiseaseTick']
   body='\n'.join(method(cpp,'uint32 DamageOverTime::'+name+'(') for name in names)
   body+='\n'+method(cpp,'float DamageOverTime::reduceTick(')
   (path/'cm_ticks.inc').write_text(body)
   entry=(NATIVE/'creature/damageovertime/DamageOverTimeList.cpp').read_text()
   start=entry.index('\tif (strength == 0 || duration == 0)',entry.index('uint32 DamageOverTimeList::addDot('));end=entry.index('\n\tif (pool == CreatureAttribute::UNKNOWN)',start)
   (path/'cm_entry.inc').write_text('int dotEntry(CreatureObject* victim,uint64 dotType,int duration,float potency,uint32 defense,int strength,uint64 objectID){'+entry[start:end]+'return duration;}')
   run=subprocess.run(['c++','-std=c++17','-I'+directory,'-I'+str(ROOT),'-I'+str(ROOT/'server/combat'),str(ROOT/'tests/combat_medic_effects_native.cpp'),'-o',str(path/'check')],capture_output=True,text=True,timeout=60)
   self.assertEqual(run.returncode,0,run.stderr)
   run=subprocess.run([str(path/'check')],capture_output=True,text=True,timeout=15)
   self.assertEqual(run.returncode,0,run.stdout+run.stderr);print(run.stdout.strip())

 def test_channels_and_serialized_lifecycle(self):
  for name in ('CombatMedicPolicy.h','SwgxrCombatMedicEffects.h'):
   self.assertEqual((ROOT/'server/medic'/name).read_bytes(),(NATIVE/'creature/commands'/name).read_bytes())
  command=(NATIVE/'creature/commands/DotPackCommand.h').read_text()
  self.assertNotIn('setNextAllowedMoveTime',command)
  self.assertNotIn('getServerObjectCRC()',command)
  self.assertIn('STRING_HASHCODE("swgxr_cm_poison")',command)
  self.assertIn('STRING_HASHCODE("swgxr_cm_disease")',command)
  self.assertEqual(command.count('decreaseUseCount()'),1)
  lifecycle=(NATIVE/'creature/damageovertime/DamageOverTime.cpp').read_text()
  self.assertEqual(lifecycle.count('medicalMode=dot.medicalMode'),2)
  self.assertIn('addSerializableVariable("medicalMode", &medicalMode)',lifecycle)
  self.assertIn('j["medicalMode"]=t.medicalMode',lifecycle)
  channels=(NATIVE/'creature/damageovertime/DamageOverTimeList.cpp').read_text()
  self.assertIn('if(cmPoison || cmDisease)newDot.configureCombatMedic(cmDisease,authoredDuration)',channels)
  self.assertIn('dotType == CreatureState::DISEASED && !cmDisease',channels)
  self.assertIn('newDot.getStrength() >= dot.getStrength()',channels)
  self.assertIn('newDot.setNextTick(dot.getNextTick())',channels)

if __name__=='__main__':unittest.main()
