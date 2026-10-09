"""Compile production medicine normalization, exact-item rules and Doctor bridge."""
from pathlib import Path
import subprocess
import tempfile
import unittest
import re
from tests.test_pistoleer_native import method
ROOT=Path(__file__).resolve().parents[1]
class DoctorCareNative(unittest.TestCase):
 def test_native_care(self):
  with tempfile.TemporaryDirectory(prefix='swgxr-doctor-care-') as directory:
   path=Path(directory)
   for name,target in [('CoreCuMedicine','medicine'),('SwgxrMedicalItem','item'),('SwgxrDoctor','bridge')]:
    text=(ROOT/f'server/medic/{name}.h').read_text()
    (path/f'doctor_{target}.inc').write_text(text[text.index(f'class {name}'):])
   source=(ROOT/'server/medic/SwgxrMedic.h').read_text()
   receipt=source[source.index('   auto raw=c->getPlayerObject()->getScreenPlayData("swgxr_medic","receipts")'):source.index('   if(!replay){')]
   commit=source.split('    receipts.push_back',1)[1].split('\n',1)[0]
   (path/'doctor_receipt.inc').write_text('class DoctorReceiptHarness { public: static Json run(CreatureObject* c,const Json& request){Json mutation;'+receipt+'if(!replay){mutation=SwgxrDoctor::run(c,request);receipts.push_back'+commit+'}return mutation;} };')
   revive=(ROOT/'vendor/Core3/MMOCoreORB/src/server/zone/objects/creature/commands/RevivePlayerCommand.h').read_text()
   (path/'doctor_revive.inc').write_text('class DoctorReviveHarness { public:'+method(revive,'\tvoid applyDebuff(')+'};')
   examine=(ROOT/'vendor/Core3/MMOCoreORB/src/server/zone/objects/tangible/pharmaceutical/StimPackImplementation.cpp').read_text()
   (path/'doctor_stim_examine.inc').write_text('class DoctorStimExamineHarness:public PharmaceuticalObject { public: struct Self {StimPack* value;StimPack* getReferenceUnsafeStaticCast(){return value;}}; Self _this{this}; int medicineUseRequired=0; void describe(AttributeListMessage* msg,CreatureObject* object){'+method(examine,'    if(!isRangedStimPack() && !isDroidRepairKit() && !isPetStimPack() && object && object->isPlayerCreature()){')+'} };')
   result=subprocess.run(['c++' ,'-std=c++17','-I'+directory,'-I'+str(ROOT),'-I'+str(ROOT/'server/combat'),str(ROOT/'tests/doctor_care_native.cpp'),'-o',str(path/'check')],capture_output=True,text=True,timeout=60)
   self.assertEqual(result.returncode,0,result.stderr)
   result=subprocess.run([str(path/'check')],capture_output=True,text=True,timeout=15)
   self.assertEqual(result.returncode,0,result.stdout+result.stderr)
   print(result.stdout.strip())
 def test_command_sites_and_mirrors(self):
  native=ROOT/'vendor/Core3/MMOCoreORB/src/server/zone/objects/creature/commands'
  for name in ['CoreCuMedicine.h','DoctorCarePolicy.h','SwgxrMedic.h','SwgxrDoctor.h']:
   self.assertEqual((ROOT/'server/medic'/name).read_bytes(),(native/name).read_bytes())
  damage=(native/'HealDamageCommand.h').read_text()
  self.assertIn('CoreCuMedicine::combatStim(creature, targetCreature, rangeStim)',damage)
  self.assertIn('CoreCuMedicine::stim(creature, targetCreature, stimPack)',damage)
  self.assertIn('CoreCuMedicine::woundPack(creature,creatureTarget,attribute,woundPack->getEffectiveness()/200.)',(native/'HealWoundCommand.h').read_text())
  self.assertIn('corecu::doctorcare::grogginess(creature->getBaseHAM(i))',(native/'RevivePlayerCommand.h').read_text())

 def test_tier_intervals_match_original_recipes(self):
  base=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/object/tangible/medicine/crafted'
  for tier,lo,hi in [('a',75,100),('b',75,200),('c',100,400),('d',150,700),('e',200,1000)]:
   text=(base/f'crafted_stimpack_sm_s1_{tier}.lua').read_text()
   minimum=re.search(r'experimentalMin = \{([^}]+)\}',text).group(1).split(',')
   maximum=re.search(r'experimentalMax = \{([^}]+)\}',text).group(1).split(',')
   self.assertEqual((int(minimum[2]),int(maximum[2])),(lo,hi))
  native=ROOT/'vendor/Core3/MMOCoreORB/src/server/zone/objects'
  examine=(native/'tangible/pharmaceutical/StimPackImplementation.cpp').read_text()
  self.assertIn('CoreCuMedicine::stim(object,object,_this.getReferenceUnsafeStaticCast(),false)',examine)
  self.assertIn('before patient battle fatigue and spice effects',examine)
  inventory=(native/'creature/commands/SwgxrInventory.h').read_text()
  for field in ['medical_healing_amount','medical_healing_percent','medical_healing_preview_scope','medical_stim_tier','medical_stim_quality']:
   self.assertIn('"'+field+'"',inventory)
