import unittest
from tools.deploy.runtime import native_initialized

class NativeReadiness(unittest.TestCase):
    def test_supported_native_markers(self):
        for name in ('CoreCU', 'Core'):
            self.assertTrue(native_initialized('(12 s) ['+name+'] initialized\nREADY'))
    def test_other_initialization_is_not_native_ready(self):
        for text in ('', '[CoreCU] Server start', '[DistributedObjectBroker] initialized', '[Zone] initialized'):
            self.assertFalse(native_initialized(text))

    def test_failed_start_also_gracefully_saves_native_child(self):
        from pathlib import Path
        unit=Path('tools/deploy/systemd/swgxr-core3.service.in').read_text()
        self.assertIn('ExecStopPost=/usr/bin/python3 @ROOT@/tools/deploy/runtime.py stop-core',unit)
