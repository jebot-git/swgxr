"""Compile production JtL security methods against isolated native objects."""
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def function(source, signature):
    start = source.index(signature)
    brace = source.index('{', start)
    depth = 1
    for end in range(brace + 1, len(source)):
        depth += (source[end] == '{') - (source[end] == '}')
        if depth == 0:
            return source[start:end + 1]
    raise AssertionError('Unterminated production function: ' + signature)


class JtlCrewNativeTests(unittest.TestCase):
    def test_actual_boarding_and_native_certification(self):
        source = (ROOT / 'server/jtl/SwgxrJtl.h').read_text()
        signatures = ['static ShipControlDevice* device(', 'static bool yacht(',
            'static void requirePilot(', 'static bool gunship(', 'static bool supported(',
            'static int capacity(', 'static bool alone(', 'static void boardingEligible(',
            'static ShipObject* owned(']
        original = (ROOT / 'vendor/Core3/MMOCoreORB/src/server/zone/objects/ship/ShipObjectImplementation.cpp').read_text()
        certification = function(original, 'bool ShipObjectImplementation::canBePilotedBy(')
        with tempfile.TemporaryDirectory(prefix='swgxr-crew-native-') as folder:
            path = Path(folder)
            (path / 'jtl_crew_methods.inc').write_text('\n'.join(function(source, signature) for signature in signatures))
            (path / 'original_certification.inc').write_text(certification.replace('ShipObjectImplementation::', 'ShipObject::', 1))
            build = subprocess.run(['c++', '-std=c++17', '-Wall', '-Wextra', '-I' + folder,
                '-I' + str(ROOT / 'vendor/Core3/MMOCoreORB/utils/engine3/MMOEngine/src'),
                str(ROOT / 'tests/jtl_crew_native.cpp'), '-o', str(path / 'check')],
                capture_output=True, text=True, timeout=60)
            self.assertEqual(build.returncode, 0, build.stderr)
            run = subprocess.run([str(path / 'check')], capture_output=True, text=True, timeout=15)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            print(run.stdout.strip())

    def test_request_and_approval_revalidate_same_production_gate(self):
        source = (ROOT / 'server/jtl/SwgxrJtl.h').read_text()
        action = function(source, 'static void boardingAction(')
        self.assertEqual(len(re.findall(r'boardingEligible\(', action)), 2)
        request, approval = action.split('if(action=="return_ship")', 1)
        self.assertIn('boardingEligible(c,own,host)', request)
        self.assertIn('boardingEligible(guest,own,host)', approval)
        self.assertLess(approval.index('boardingEligible(guest,own,host)'), approval.index('store(guest,own,true)'))
        self.assertIn('pending.at("ship_id")!=id(own)', approval)
        self.assertIn('Locker hostLock(host,c)', approval)
        self.assertIn('Locker shipLock(own,c)', approval)


if __name__ == '__main__':
    unittest.main()
