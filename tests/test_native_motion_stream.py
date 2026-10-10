from pathlib import Path
import subprocess
import tempfile
import unittest
ROOT = Path(__file__).resolve().parents[1]
class NativeMotionStreamTest(unittest.TestCase):
    def test_native_stream(self):
        with tempfile.TemporaryDirectory() as d:
            binary = str(Path(d)/'motion')
            subprocess.run(['c++', '-std=c++17', '-pthread', '-I'+str(ROOT),
                '-I'+str(ROOT/'vendor/Core3/MMOCoreORB/utils/engine3/MMOEngine/src'),
                str(ROOT/'tests/native_motion_stream.cpp'), '-o', binary], check=True, timeout=60)
            subprocess.run([binary], check=True, timeout=15)
