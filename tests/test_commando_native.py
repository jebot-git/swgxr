"""Compile the production Commando bridge against isolated Core3 dependencies."""
from pathlib import Path
import subprocess
import tempfile
import unittest
import re
import sys
from tests.test_pistoleer_native import method
ROOT=Path(__file__).resolve().parents[1]
class CommandoNative(unittest.TestCase):
 def test_production_heavy_delivery(self):
  source=(ROOT/'server/combat/SwgxrCommando.h').read_text()
  source=source[source.index('class SwgxrCommandoStrike'):]
  with tempfile.TemporaryDirectory(prefix='swgxr-commando-') as directory:
   path=Path(directory);(path/'commando_native.inc').write_text(source)
   (path/'commando_loadout_family.inc').write_text('class NativeLoadoutFamily {public:'+method((ROOT/'server/combat/SwgxrCombatLoadout.h').read_text(),' static std::string family(')+'};')
   build=subprocess.run(['c++','-std=c++17','-I'+directory,'-I'+str(ROOT),str(ROOT/'tests/commando_native.cpp'),'-o',str(path/'check')],capture_output=True,text=True,timeout=60)
   self.assertEqual(build.returncode,0,build.stderr)
   run=subprocess.run([str(path/'check')],capture_output=True,text=True,timeout=10)
   self.assertEqual(run.returncode,0,run.stdout+run.stderr);print(run.stdout.strip())
 def test_patch_integration(self):
  native=ROOT/'vendor/Core3/MMOCoreORB/src/server/zone/objects/creature'
  for name in ('CommandoPolicy.h','SwgxrCommando.h','SwgxrBlastSight.h'):
   self.assertEqual((ROOT/'server/combat'/name).read_bytes(),(native/'commands'/name).read_bytes())
  live=(native/'commands/SwgxrLiveCombat.h').read_text()
  self.assertLess(live.index('verb=="fire" && SwgxrCommando::supported'),live.index('if(verb=="fire"){'))
  self.assertIn('static Mutex mutex;',live)
  lifecycle=(native/'damageovertime/DamageOverTimeList.cpp').read_text()
  self.assertIn('if(commandoBurn)newDot.configureCommandoBurn(strength)',lifecycle)
  self.assertIn('else if(fencerBleed || commandoBurn)',lifecycle)
  cpp=(ROOT/'vendor/Core3/MMOCoreORB/src/server/zone/managers/combat/CombatManager.cpp').read_text()
  self.assertEqual(cpp.count('if(data.getCommand()->getPhysicalDamageCap()>0)'),3)
 def test_production_policy(self):
  with tempfile.TemporaryDirectory(prefix='swgxr-commando-policy-') as directory:
   binary=Path(directory)/'check'
   build=subprocess.run(['c++','-std=c++17','-I'+str(ROOT),'-I'+str(ROOT/'server/combat'),str(ROOT/'tests/commando_policy.cpp'),'-o',str(binary)],capture_output=True,text=True,timeout=60)
   self.assertEqual(build.returncode,0,build.stderr)
   run=subprocess.run([str(binary)],capture_output=True,text=True,timeout=10)
   self.assertEqual(run.returncode,0,run.stdout+run.stderr);print(run.stdout.strip())

 def test_original_unlocks_and_heavy_arrangements(self):
  sys.path.insert(0,str(ROOT/'tools/assets'))
  from server.character_protocol import assets
  from character_formats import datatable
  from interior_layout import template_properties
  from prepare_inventory import arrangements
  source=assets();rows={r['NAME']:r for r in datatable(source.read('datatables/skill/skills.iff'))}
  self.assertIn('fireAcidCone1',rows['combat_commando_support_02']['COMMANDS'].split(','))
  self.assertIn('fireAcidCone2',rows['combat_commando_master']['COMMANDS'].split(','))
  expected='abstract/slot/arrangement/wearables/hold_both.iff'
  self.assertEqual(arrangements(source.read,expected),[['hold_r','hold_l']])
  for name in ('heavy_particle_beam','heavy_acid_beam','heavy_lightning_beam','heavy_rocket_launcher'):
   original=template_properties(source.read,'object/weapon/ranged/heavy/shared_'+name+'.iff')
   self.assertEqual(arrangements(source.read,original['arrangementDescriptorFilename']),[[]])
   lua=(ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/object/weapon/ranged/heavy'/f'{name}.lua').read_text()
   authored=re.search(r'arrangementDescriptorFilename\s*=\s*"([^"]+)"',lua).group(1)
   self.assertEqual(authored,expected)
  native=(ROOT/'vendor/Core3/MMOCoreORB/src/server/zone/objects/scene/SceneObjectImplementation.cpp').read_text()
  self.assertIn('return &templateObject->getArrangementDescriptors().get(idx);',native)
  self.assertIn('return templateObject->getArrangementDescriptors().size();',native)
  equipment=(ROOT/'vendor/Core3/MMOCoreORB/src/server/zone/objects/creature/commands/SwgxrEquipment.h').read_text()
  self.assertIn('c->canAddObject(o,4,error)',equipment)
  self.assertIn('c->setWeapon(weapon,true)',equipment)
