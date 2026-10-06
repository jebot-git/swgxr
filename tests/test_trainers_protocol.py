import struct,unittest
from unittest.mock import patch
from server.services_protocol import command,snapshot
from server.datapad_protocol import datapad
class TrainerProtocolTests(unittest.TestCase):
 def test_skill_identity_and_idempotency(self):
  base={'terminal_id':'123','request_id':'trainer_test_001','skill_id':'combat_marksman_pistol_01'}
  self.assertEqual(command('trainer_train',base)['skill_id'],base['skill_id'])
  for bad in ('',None,True,'../grant','a'*97,'Marksman',12):
   with self.assertRaises(ValueError):command('trainer_train',dict(base,skill_id=bad))
  for missing in ('terminal_id','request_id','skill_id'):
   data=dict(base);data.pop(missing)
   with self.assertRaises(ValueError):command('trainer_train',data)
 def test_source_labels_and_complete_owner_state(self):
  raw={'source_kind':'core3_services','character_id':'11','player':{},'skills':['science_medic_novice'],'skills_complete':True,'experience':{'medical':42},'experience_complete':True,'terminal':{'kind':'trainer','trainer_text':'@skill_teacher:trainer_medic','skills':[{'id':'science_medic_injury_01','name':'@skl_n:science_medic_injury_01','description':'@skl_d:science_medic_injury_01','xp_name':'@exp_n:medical','eligible':False,'blocked_reason':'Not enough experience.'}]}}
  with patch('server.services_protocol.display',side_effect=lambda table,key,fallback:table+'/'+key):out=snapshot(raw,'11')['state']
  self.assertEqual(out['terminal']['trainer_text'],'skill_teacher/trainer_medic');self.assertEqual(out['terminal']['skills'][0]['xp_name'],'exp_n/medical')
  self.assertEqual(out['experience'],{'medical':42});self.assertTrue(out['experience_complete']);self.assertTrue(out['skills_complete'])
  self.assertEqual(raw['terminal']['trainer_text'],'@skill_teacher:trainer_medic')
 def test_play8_full_experience_decode(self):
  def asc(value):data=value.encode();return struct.pack('<H',len(data))+data
  xp=struct.pack('<II',2,0)+b'\0'+asc('medical')+struct.pack('<i',124)+b'\0'+asc('crafting_general')+struct.pack('<i',0)
  ghost={'type':0x504c4159,'parentId':'11','baseline8':(xp+struct.pack('<II',0,0)).hex(),'baseline9':(struct.pack('<II',0,0)+bytes(16)+struct.pack('<II',0,0)).hex()}
  data={'variables':{'replication':{'objects':{'o12':ghost,'o13':{'parentId':'11','templateCrc':1},'o11':{}}}}}
  with patch('server.datapad_protocol.template_names',return_value={1:'object/tangible/datapad/shared_character_datapad.iff'}):value=datapad(data,'11')
  self.assertEqual(value['experience'],{'medical':124,'crafting_general':0});self.assertTrue(value['experience_complete'])
 def test_exact_supported_original_catalogues(self):
  import re
  from pathlib import Path
  root=Path(__file__).resolve().parents[1];source=(root/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/trainers/trainerData.lua').read_text();header=(root/'server/services/SwgxrTrainerCatalog.h').read_text()
  from server.profession_scope import TRAINERS
  self.assertEqual(set(re.findall(r'\{"(trainer_[a-z0-9]+)",',header)),{'trainer_'+p for p in TRAINERS})
  for profession in TRAINERS:
   skills=re.findall(r'"([a-z0-9_]+)"',re.search(r'\btrainer_'+profession+r'\s*=\s*\{([^}]+)\}',source).group(1))
   self.assertEqual(len(skills),18)
   compiled=re.findall(r'"([a-z0-9_]+)"',re.search(r'\{"trainer_'+profession+r'",\s*\{([^}]+)\}',header).group(1))
   self.assertEqual(skills,compiled)
if __name__=='__main__':unittest.main()
