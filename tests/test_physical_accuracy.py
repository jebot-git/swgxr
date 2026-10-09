"""Run the actual patched native hit resolver with deterministic dependency fixtures."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

class PhysicalAccuracy(unittest.TestCase):
 def test_native_resolver_does_not_reroll_accepted_player_contacts(self):
  source = ROOT / 'vendor/Core3/MMOCoreORB/src/server/zone/managers/combat/CombatManager.cpp'
  text = source.read_text()
  start = text.index('int CombatManager::getHitChance(')
  end = text.index('\nfloat CombatManager::hitChanceEquation(', start)
  with tempfile.TemporaryDirectory(prefix='swgxr-physical-accuracy-') as directory:
   path=Path(directory)
   (path/'physical_accuracy_resolver.inc').write_text(text[start:end])
   result=subprocess.run(['c++','-std=c++17','-pthread','-I'+directory,'-I'+str(ROOT),str(ROOT/'tests/physical_accuracy.cpp'),'-o',str(path/'check')],capture_output=True,text=True,timeout=30)
   self.assertEqual(result.returncode,0,result.stderr)
   result=subprocess.run([str(path/'check')],capture_output=True,text=True,timeout=10)
   self.assertEqual(result.returncode,0,result.stdout+result.stderr)
   self.assertIn('68 native physical-accuracy resolver cases passed',result.stdout)
   print(result.stdout.strip())
