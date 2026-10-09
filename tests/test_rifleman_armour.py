"""Run the production armour resolver against per-projectile penetration fixtures."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class RiflemanArmour(unittest.TestCase):
    def test_receipt_local_penetration_preserves_other_mitigation(self):
        source = (ROOT / 'vendor/Core3/MMOCoreORB/src/server/zone/managers/combat/CombatManager.cpp').read_text()
        start = source.index('int CombatManager::getArmorReduction(')
        end = source.index('\nint CombatManager::getArmorTurretReduction(', start)
        with tempfile.TemporaryDirectory(prefix='swgxr-rifleman-armour-') as directory:
            path = Path(directory)
            (path / 'rifleman_armour.inc').write_text(source[start:end])
            result = subprocess.run(['c++', '-std=c++17', '-I'+directory, '-I'+str(ROOT),
                                     str(ROOT / 'tests/rifleman_armour.cpp'), '-o', str(path / 'check')],
                                    capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)
            result = subprocess.run([str(path / 'check')], capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
            print(result.stdout.strip())


if __name__ == '__main__':
    unittest.main()
