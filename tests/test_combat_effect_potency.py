"""Execute real specialist policies and compare their resistance-aware potency."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
NATIVE = ROOT / 'vendor/Core3/MMOCoreORB/src/server/zone/objects/creature/commands'


class CombatEffectPotency(unittest.TestCase):
    def test_actual_policies_and_existing_specialist_invariants(self):
        with tempfile.TemporaryDirectory(prefix='swgxr-effect-potency-') as directory:
            for fixture in ['combat_effect_potency', 'fencer_policy', 'pikeman_policy', 'melee_traps_policy']:
                with self.subTest(fixture=fixture):
                    binary = Path(directory) / fixture
                    result = subprocess.run(['c++', '-std=c++17', '-I'+str(ROOT),
                                             '-I'+str(ROOT/'server/combat'),
                                             str(ROOT/'tests'/f'{fixture}.cpp'), '-o', str(binary)],
                                            capture_output=True, text=True, timeout=30)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=10)
                    self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
                    print(result.stdout.strip())

    def test_native_consumers_share_installed_policies(self):
        for name in ['CoreCuPolicy.h', 'FencerPolicy.h', 'PikemanPolicy.h', 'CarbineerPolicy.h',
                     'SwgxrFencer.h', 'SwgxrCarbineer.h']:
            self.assertEqual((ROOT/'server/combat'/name).read_bytes(), (NATIVE/name).read_bytes(), name)
        trap = (ROOT/'vendor/Core3/MMOCoreORB/src/server/zone/objects/creature/events/ThrowTrapTask.h').read_text()
        self.assertIn('corecu::trapStatusChance(resistance, CoreCuCombat::trapBonus(attacker))', trap)
