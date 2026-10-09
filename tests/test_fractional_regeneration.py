"""Execute the production CreatureObject regeneration method with isolated dependencies."""
from pathlib import Path
import subprocess
import tempfile
import unittest
from tests.test_pistoleer_native import method

ROOT = Path(__file__).resolve().parents[1]
CREATURE = ROOT / 'vendor/Core3/MMOCoreORB/src/server/zone/objects/creature'


class FractionalRegeneration(unittest.TestCase):
    def test_native_elapsed_regeneration(self):
        source = (CREATURE / 'CreatureObjectImplementation.cpp').read_text()
        with tempfile.TemporaryDirectory(prefix='swgxr-fractional-regen-') as directory:
            path = Path(directory)
            (path / 'regen_native.inc').write_text(method(source, 'void CreatureObjectImplementation::activateHAMRegeneration('))
            resources = (ROOT / 'server/combat/CoreCuResources.h').read_text()
            (path / 'regen_resources.inc').write_text('struct CoreCuResources {' + method(resources, ' static double regen(') + '};')
            preparation = (ROOT / 'server/combat/SwgxrDoctorPreparation.h').read_text()
            (path / 'regen_strength.inc').write_text('struct SwgxrDoctorPreparation {' + method(preparation, ' static int strength(') + '};')
            result = subprocess.run(['c++', '-std=c++17', '-I'+directory, '-I'+str(ROOT), str(ROOT / 'tests/fractional_regeneration_native.cpp'), '-o', str(path / 'check')], capture_output=True, text=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stderr)
            result = subprocess.run([str(path / 'check')], capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            print(result.stdout.strip())

    def test_transient_lifecycle_and_installed_policy(self):
        idl = (CREATURE / 'CreatureObject.idl').read_text()
        source = (CREATURE / 'CreatureObjectImplementation.cpp').read_text()
        for pool in ('Health', 'Action', 'Mind'):
            self.assertIn(f'protected transient double corecu{pool}RegenCarry;', idl)
            self.assertIn(f'corecu{pool}RegenCarry', method(source, 'void CreatureObjectImplementation::initializeTransientMembers('))
            self.assertIn(f'corecu{pool}RegenCarry', method(source, 'void CreatureObjectImplementation::setHAM('))
            self.assertIn(f'corecu{pool}RegenCarry', method(source, 'void CreatureObjectImplementation::setPosture('))
        self.assertIn('corecuHealthRegenCarry = 0.', method(source, 'void CreatureObjectImplementation::setCombatState('))
        self.assertIn('corecuHealthRegenCarry = 0.', method(source, 'bool CreatureObjectImplementation::setState('))
        self.assertEqual((ROOT / 'server/combat/CoreCuRegenPolicy.h').read_bytes(), (CREATURE / 'commands/CoreCuRegenPolicy.h').read_bytes())
