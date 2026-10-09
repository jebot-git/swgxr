"""Exercise actual CM medicine normalization, area selection and HealMind command."""
from pathlib import Path
import re
import subprocess
import tempfile
import unittest
from tests.test_pistoleer_native import method

ROOT=Path(__file__).resolve().parents[1]
NATIVE=ROOT/'vendor/Core3/MMOCoreORB/src/server/zone/objects/creature/commands'


class CombatMedicHealing(unittest.TestCase):
    def test_native_healing_and_transfers(self):
        with tempfile.TemporaryDirectory(prefix='swgxr-cm-healing-') as directory:
            path=Path(directory)
            medicine=(ROOT/'server/medic/CoreCuMedicine.h').read_text()
            (path/'cm_medicine.inc').write_text(medicine[medicine.index('class CoreCuMedicine'):])
            mind=(NATIVE/'HealMindCommand.h').read_text()
            (path/'cm_mind.inc').write_text('class MindHarness: public QueueCommand {public:'+method(mind,'\tint doQueueCommand(')+'};')
            heal=(NATIVE/'HealDamageCommand.h').read_text()
            (path/'cm_area.inc').write_text('class AreaHarness: public QueueCommand {public: mutable std::vector<uint64> treated; void doAreaMedicActionTarget(CreatureObject* c,CreatureObject* target,StimPack* pack) const {treated.push_back(target->getObjectID()); target->healDamage(c,0,CoreCuMedicine::combatStim(c,target,pack));}\n'+method(heal,'\tbool checkTarget(')+'\n'+method(heal,'    bool areaTargetEligible(')+'\n'+method(heal,'    void handleArea(')+'};')
            result=subprocess.run(['c++','-std=c++17','-I'+directory,'-I'+str(ROOT),'-I'+str(ROOT/'server/combat'),str(ROOT/'tests/combat_medic_healing.cpp'),'-o',str(path/'check')],capture_output=True,text=True,timeout=60)
            self.assertEqual(result.returncode,0,result.stderr)
            result=subprocess.run([str(path/'check')],capture_output=True,text=True,timeout=15)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            print(result.stdout.strip())

    def test_real_recipe_quality_bounds_and_native_routes(self):
        folder=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/object/tangible/medicine/crafted'
        for family,bounds in [('damage',[(75,150),(75,300),(100,500),(150,700),(200,1000)]),('area',[(100,300),(100,500),(100,700)])]:
            for tier,(lo,hi) in enumerate(bounds):
                text=(folder/f'medpack_grenade_{family}_{chr(97+tier)}.lua').read_text()
                values=[int(re.search(r'experimental'+kind+r' = \{([^}]+)\}',text)[1].split(',')[2]) for kind in ['Min','Max']]
                self.assertEqual(values,[lo,hi])
        for name in ['CoreCuMedicine.h','CombatMedicHealingPolicy.h']:
            self.assertEqual((ROOT/'server/medic'/name).read_bytes(),(NATIVE/name).read_bytes())
        heal=(NATIVE/'HealDamageCommand.h').read_text()
        self.assertIn('CoreCuMedicine::combatStim(creature, targetCreature, rangeStim)',heal)
        self.assertIn('CoreCuMedicine::stim(creature, targetCreature, stimPack)',heal)
        inspect=(ROOT/'vendor/Core3/MMOCoreORB/src/server/zone/objects/tangible/pharmaceutical/RangedStimPackImplementation.cpp').read_text()
        self.assertIn('CoreCuMedicine::combatStim(object, object, _this.getReferenceUnsafeStaticCast(), false)',inspect)
        self.assertIn('Up to 5 including the primary patient',inspect)
        self.assertIn('CoreCuMedicine::combatStimRange',inspect)
