"""Exercise actual Marksman target/effect bodies with deterministic native dependencies."""
from pathlib import Path
import subprocess
import tempfile
import unittest
ROOT=Path(__file__).resolve().parents[1]
class MarksmanNative(unittest.TestCase):
 def test_native_effects(self):
  source=(ROOT/'server/combat/SwgxrMarksman.h').read_text()
  methods=[]
  for signature in (' static bool learned(', ' static bool bleedImproved(', ' static bool bountyBleed(', ' static double bleedFraction(', ' static int actionCost(', ' static double damage(', ' static bool targetReady(', ' static void effects('):
   start=source.index(signature);at=source.index('{',start);depth=1;end=at+1
   while depth:
    depth+=(source[end]=='{')-(source[end]=='}');end+=1
   methods.append(source[start:end])
  with tempfile.TemporaryDirectory(prefix='swgxr-marksman-') as directory:
   path=Path(directory);(path/'marksman_effects.inc').write_text('class SwgxrMarksman { public:\n'+'\n'.join(methods)+'\n};')
   r=subprocess.run(['c++','-std=c++17','-I'+directory,'-I'+str(ROOT),str(ROOT/'tests/marksman_native.cpp'),'-o',str(path/'check')],capture_output=True,text=True,timeout=30)
   self.assertEqual(r.returncode,0,r.stderr)
   r=subprocess.run([str(path/'check')],capture_output=True,text=True,timeout=10)
   self.assertEqual(r.returncode,0,r.stdout+r.stderr);print(r.stdout.strip())
