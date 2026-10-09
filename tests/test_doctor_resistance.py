"""Execute production resistance/preparation resolution and audit raw DoT producer reads."""
from pathlib import Path
import json
import subprocess
import tempfile
import unittest
ROOT=Path(__file__).resolve().parents[1]
NATIVE=ROOT/'vendor/Core3/MMOCoreORB/src/server/zone'

class DoctorResistance(unittest.TestCase):
 def test_native_resolution(self):
  with tempfile.TemporaryDirectory(prefix='swgxr-doctor-resistance-') as directory:
   path=Path(directory)
   for source,typename,destination in [('CoreCuCombat.h','CoreCuCombat','corecu_combat_native.inc'),('SwgxrDoctorPreparation.h','SwgxrDoctorPreparation','doctor_preparation_native.inc')]:
    data=(ROOT/'server/combat'/source).read_text();(path/destination).write_text(data[data.index('class '+typename):])
   source=(NATIVE/'objects/creature/damageovertime/DamageOverTimeList.cpp').read_text()
   start=source.index('\tif (strength == 0 || duration == 0)',source.index('uint32 DamageOverTimeList::addDot('));end=source.index('\n\tif (pool == CreatureAttribute::UNKNOWN)',start)
   (path/'doctor_dot_entry.inc').write_text('int doctorDotEntry(CreatureObject* victim,uint64 dotType,int duration,float potency,uint32 defense,int strength){uint64 objectID=0;'+source[start:end]+'\nreturn duration;}')
   source=(NATIVE/'objects/creature/damageovertime/DamageOverTime.cpp').read_text()
   start=source.index('uint32 DamageOverTime::doDiseaseTick(');end=source.index('\nuint32 DamageOverTime::doForceChokeTick(',start)
   (path/'doctor_disease_tick.inc').write_text('class DamageOverTime {public:int strength=100,attribute=3,medicalMode=0;uint32 doDiseaseTick(CreatureObject*,CreatureObject*);};\n'+source[start:end])
   config=json.loads((ROOT/'server/combat/corecu_professions.json').read_text())
   profiles='namespace corecu {struct Profession {const char* name;double ratings[10];};constexpr const char* REVISION="native-fixture";constexpr Profession PROFESSIONS[]={'+','.join('{'+json.dumps(name)+',{'+','.join(map(str,values))+'}}' for name,values in config['professions'].items())+'};}'
   (path/'corecu_profiles.inc').write_text(profiles)
   r=subprocess.run(['c++','-std=c++17','-I'+directory,'-I'+str(ROOT),'-I'+str(ROOT/'server/combat'),str(ROOT/'tests/doctor_resistance_native.cpp'),'-o',str(path/'check')],capture_output=True,text=True,timeout=30)
   self.assertEqual(r.returncode,0,r.stderr)
   r=subprocess.run([str(path/'check')],capture_output=True,text=True,timeout=10)
   self.assertEqual(r.returncode,0,r.stdout+r.stderr);print(r.stdout.strip())

 def test_producers_strip_medical_contribution_before_shared_resolution(self):
  combat=(NATIVE/'managers/combat/CombatManager.cpp').read_text()
  area=combat[combat.index('void CombatManager::applyDots('):combat.index('uint8 CombatManager::getPoolForDot')]
  self.assertIn('CoreCuCombat::rawModifier(defender,defenseMods.get(j))',area)
  for status in ('poison','disease'):
   self.assertIn('CoreCuCombat::rawModifier(defender,"resistance_'+status+'")',area)
   self.assertNotIn('defender->getSkillMod("resistance_'+status+'")',area)
  packs=(NATIVE/'objects/creature/commands/DotPackCommand.h').read_text()
  self.assertEqual(packs.count('CoreCuCombat::rawModifier(targetCreature,"resistance_poison")'),1)
  self.assertEqual(packs.count('CoreCuCombat::rawModifier(targetCreature,"resistance_disease")'),1)
  common=(NATIVE/'objects/creature/damageovertime/DamageOverTimeList.cpp').read_text()
  self.assertEqual(common.count('CoreCuCombat::rating(victim,CoreCuCombat::dotIndex(dotType),defense)'),1)
  self.assertIn(':corecu::statusChance(potency,rating)',common)
  self.assertIn('if (potency >= 0 && System::random(100) >= chance)',common)
  self.assertIn('dotType == CreatureState::ONFIRE && victim->hasState(CreatureState::SWIMMING)',common)
  self.assertIn('defender->hasDotImmunity(effect.getDotType())',area)
  self.assertIn('defender->hasDotImmunity(type)',area)

 def test_mirrors(self):
  for name in ('CoreCuCombat.h','CoreCuPolicy.h'):
   self.assertEqual((ROOT/'server/combat'/name).read_bytes(),(NATIVE/'objects/creature/commands'/name).read_bytes())
