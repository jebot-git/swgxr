"""Compile actual Combat Medic bridge, helper, item ownership and receipt code."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class CombatMedicBridge(unittest.TestCase):
    def test_native_bridge(self):
        with tempfile.TemporaryDirectory(prefix='swgxr-cm-bridge-') as directory:
            path = Path(directory)
            for name, output in [('SwgxrMedicalItem', 'item'),
                                 ('SwgxrCombatMedicEffects', 'effects'),
                                 ('SwgxrCombatMedic', 'bridge')]:
                source = (ROOT / 'server/medic' / (name + '.h')).read_text()
                (path / ('cm_' + output + '.inc')).write_text(source[source.index('class ' + name):])
            source = (ROOT / 'server/medic/SwgxrMedic.h').read_text()
            receipt = source[source.index('   auto raw=c->getPlayerObject()->getScreenPlayData("swgxr_medic","receipts")'):source.index('   if(!replay){')]
            commit = source.split('    receipts.push_back', 1)[1].split('\n', 1)[0]
            (path / 'cm_receipt.inc').write_text('class CombatMedicReceiptHarness {public: static Json run(CreatureObject* c,const Json& request){Json mutation;' + receipt + 'if(!replay){mutation=SwgxrCombatMedic::run(c,request);receipts.push_back' + commit + '}return mutation;}};')
            result = subprocess.run(['c++', '-std=c++17', '-I' + directory, '-I' + str(ROOT), '-I' + str(ROOT / 'server/combat'),
                                     str(ROOT / 'tests/combat_medic_bridge_native.cpp'), '-o', str(path / 'check')],
                                    capture_output=True, text=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stderr)
            result = subprocess.run([str(path / 'check')], capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            print(result.stdout.strip())

    def test_installed_bridge_and_route(self):
        for name in ('SwgxrMedic.h', 'SwgxrCombatMedic.h'):
            self.assertEqual((ROOT / 'server/medic' / name).read_bytes(),
                             (ROOT / 'vendor/Core3/MMOCoreORB/src/server/zone/objects/creature/commands' / name).read_bytes())
        source = (ROOT / 'server/medic/SwgxrMedic.h').read_text()
        self.assertIn('mutation=SwgxrCombatMedic::run(c,request)', source)
        self.assertIn('SwgxrCombatMedic::snapshot(c,out["inventory"])', source)
        self.assertIn('SwgxrCombatMedic::target(c,target,out["combat_medic"])', source)


if __name__ == '__main__':
    unittest.main()
