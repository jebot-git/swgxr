"""Doctor preparation balance, real native buff helper and source recipe grants."""
from pathlib import Path
import re
import subprocess
import tempfile
import unittest
ROOT=Path(__file__).resolve().parents[1]

class DoctorPreparations(unittest.TestCase):
 def test_native_policy_and_buff_transaction(self):
  with tempfile.TemporaryDirectory(prefix='swgxr-doctor-prep-') as directory:
   path=Path(directory)
   source=(ROOT/'server/combat/SwgxrDoctorPreparation.h').read_text()
   (path/'doctor_preparation_native.inc').write_text(source[source.index('class SwgxrDoctorPreparation'):])
   r=subprocess.run(['c++','-std=c++17','-I'+directory,'-I'+str(ROOT),str(ROOT/'tests/doctor_preparations.cpp'),'-o',str(path/'check')],capture_output=True,text=True,timeout=30)
   self.assertEqual(r.returncode,0,r.stderr)
   r=subprocess.run([str(path/'check')],capture_output=True,text=True,timeout=10)
   self.assertEqual(r.returncode,0,r.stdout+r.stderr);print(r.stdout.strip())

 def test_preparation_recipes_preserve_ingredients_and_experimentation(self):
  core=ROOT/'vendor/Core3'
  for family in ['health','action','constitution','poison','disease']:
   for tier in ('abc' if family in ['poison','disease'] else 'abcd'):
    for kind in ['draft_schematic/chemistry','tangible/medicine/crafted']:
     name=f'MMOCoreORB/bin/scripts/object/{kind}/medpack_enhance_{family}_{tier}.lua'
     source=(core/name).read_text()
     baseline=subprocess.run(['git','-C',str(core),'show','HEAD:'+name],capture_output=True,text=True,check=True).stdout
     def mechanical(text):
      return '\n'.join(line for line in text.splitlines() if 'customObjectName =' not in line)
     self.assertEqual(mechanical(source),mechanical(baseline),name)
     self.assertRegex(source,r'customObjectName = "(?:Vitality|Endurance|Metabolic|Poison|Disease)')

 def test_owned_headers_match(self):
  native=ROOT/'vendor/Core3/MMOCoreORB/src/server/zone/objects/creature/commands'
  for name in ['DoctorPolicy.h','SwgxrDoctorPreparation.h','CoreCuMedicalPolicy.h','CoreCuResources.h']:
   self.assertEqual((ROOT/'server/combat'/name).read_bytes(),(native/name).read_bytes(),name)

 def test_source_groups_have_useful_doctor_rewards(self):
  from server.character_protocol import assets
  from character_formats import datatable
  skills=datatable(assets().read('datatables/skill/skills.iff'))
  rows=datatable(assets().read('datatables/crafting/schematic_group.iff'))
  wanted=[r for r in skills if r['NAME'].startswith('science_doctor_')]
  with tempfile.TemporaryDirectory(prefix='swgxr-doctor-groups-') as directory:
   path=Path(directory)
   source='#include "server/combat/CoreCuMedicalPolicy.h"\n#include <iostream>\nint main(){std::string path,group;while(std::getline(std::cin,path) && std::getline(std::cin,group)){std::cout<<(corecu::medicine::retiredMedicalTemplate(path)?"":corecu::doctor::schematicGroup(path,group))<<"\\n";}}'
   (path/'groups.cpp').write_text(source)
   subprocess.run(['c++','-std=c++17','-I'+str(ROOT),str(path/'groups.cpp'),'-o',str(path/'groups')],check=True,capture_output=True)
   output=subprocess.run([str(path/'groups')],input=''.join(r['SchematicName']+'\n'+r['GroupId']+'\n' for r in rows),text=True,capture_output=True,check=True).stdout.splitlines()
  groups={}
  for r,g in zip(rows,output):
   if g:groups.setdefault(g,[]).append(r['SchematicName'])
  for skill in wanted:
   for group in filter(None,skill['SCHEMATICS_GRANTED'].split(',')):
    self.assertTrue(groups.get(group),skill['NAME']+': '+group)
  expected={'craftMedpackBGroupC':'constitution_b','craftMedpackBGroupD':'constitution_c','craftMedpackBGroupE':'constitution_d','craftMedpackBEnhanceGroupA':'constitution_a'}
  for group,suffix in expected.items():self.assertIn('object/draft_schematic/chemistry/medpack_enhance_'+suffix+'.iff',groups[group])
  for group,tier in [('craftMedpackBEnhanceGroupB','a'),('craftMedpackBEnhanceGroupC','b'),('craftMedpackBEnhanceGroupD','c')]:
   self.assertEqual(sorted(groups[group]),sorted('object/draft_schematic/chemistry/medpack_enhance_'+family+'_'+tier+'.iff' for family in ['poison','disease']))
  preparations=[p for g in groups.values() for p in g if 'medpack_enhance_' in p]
  self.assertEqual(len(preparations),18);self.assertEqual(len(set(preparations)),18)
