"""Compile the shared native action policy and exercise deterministic latency cases."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
ROOT = Path(__file__).resolve().parents[1]


class ActionCombatNative(unittest.TestCase):
    def test_geometry_deadlines_idempotency_and_latency(self):
        with tempfile.TemporaryDirectory(prefix='swgxr-action-policy-') as directory:
            binary = str(Path(directory)/'test')
            subprocess.run(['c++', '-std=c++17', '-O2', '-Wall', '-Wextra',
                            str(ROOT/'tests/action_combat_policy.cpp'), '-o', binary], check=True, timeout=30)
            run = subprocess.run([binary], check=True, capture_output=True, text=True, timeout=15)
            rows = [json.loads(line) for line in run.stdout.splitlines()]
            self.assertEqual(len(rows), 12)
            self.assertEqual(sum(row['trials'] for row in rows), 105300)
            for row in rows:
                self.assertEqual(row['hits']+row['avoided'], row['trials'])
                self.assertEqual(row['accepted']+row['fallback'], row['trials'])
                self.assertLess(row['max_settlement_ms'], 675)
