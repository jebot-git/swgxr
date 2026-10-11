import json,math,subprocess,tempfile,unittest
from pathlib import Path
from server.action_combat import command,events
ROOT=Path(__file__).resolve().parents[1]
class GroundActionTests(unittest.TestCase):
 def test_native_policy(self):
  with tempfile.TemporaryDirectory() as folder:
   binary=str(Path(folder)/'policy');subprocess.run(['c++','-std=c++14','-Wall','-Wextra',str(ROOT/'tests/ground_action_policy.cpp'),'-o',binary],check=True)
   subprocess.run([binary],check=True)
 def test_bounded_batch_and_self_identity(self):
  lock=dict(kind='lock',actor_id='5',attack_id='6',aim_revision=1)
  hit=dict(lock,kind='contact',contact=True,coverage_start=10,coverage_end=11,sample_position=[0,0,0])
  self.assertEqual(command(dict(action='batch',receipts=[lock,hit]))['receipts'],[lock,hit])
  for change in ({'victim_id':'7'},{'sample_position':[math.nan,0,0]},{'contact':1},{'aim_revision':False}):
   with self.assertRaises(ValueError):command(dict(action='batch',receipts=[dict(hit,**change)]))
  with self.assertRaises(ValueError):command(dict(action='batch',receipts=[lock]*33))
  self.assertEqual(command(dict(action='negotiate',protocol=2,catalog_revision='a'*64))['protocol'],2)
  with self.assertRaises(ValueError):command(dict(action='negotiate',protocol=2,catalog_revision='old'))
 def test_presentation_time_is_finite_bounded_shape_and_not_contact_authority(self):
  lock=dict(kind='lock',actor_id='5',attack_id='6',aim_revision=1,presented_at=10.5)
  self.assertEqual(command(dict(action='batch',receipts=[lock]))['receipts'],[lock])
  for value in (math.nan,math.inf,-1,True,'10.5'):
   with self.assertRaises(ValueError):command(dict(action='batch',receipts=[dict(lock,presented_at=value)]))
 def test_integration_event_contract(self):
  row=dict(protocol=2,state_revision=1,sequence=500,id='5',target_id='6',encounter_id='5',attack_id='10',phase='windup',role='ranged',cell_id='0',server_now=10,start=10,delivery_at=11.4,active_at=11.733,end_at=11.9,animation_end_at=12.4,recover_at=13.8,animation='action_ground_pistol',range=64,radius=.45,cosine=.5,origin=[0,0,0],direction=[0,0,1],aim_revision=1,aim_locked=False,lock_at=10.9,age_ms=0,eligible_victim_ids=['6'],hit_policy='first_contact')
  self.assertEqual(len(events(dict(action_events=[row]),{'5':dict(cell_id='0')},0)),1)
  for change in ({'hit_policy':'piercing_lane'},{'state_revision':True},{'animation':'arbitrary'},{'range':100}):
   self.assertEqual(events(dict(action_events=[dict(row,**change)]),{'5':dict(cell_id='0')},0),[])
 def test_positive_contact_sample(self):
  row=dict(kind='contact',actor_id='5',attack_id='6',aim_revision=1,contact=True,contact_at=10.5,coverage_start=10,coverage_end=11,sample_position=[0,0,0])
  self.assertEqual(command(dict(action='batch',receipts=[row]))['receipts'],[row])
  for change in ({'contact':False},{'contact_at':float('inf')},{'contact_at':True},{'contact_at':-1}):
   with self.assertRaises(ValueError):command(dict(action='batch',receipts=[dict(row,**change)]))
 def test_special_geometry_and_explicit_victim(self):
  row=dict(protocol=2,state_revision=1,sequence=1,id='5',target_id='6',encounter_id='5',attack_id='10',phase='windup',role='ranged',cell_id='0',server_now=10,start=10,delivery_at=12,active_at=12.3,end_at=12.5,animation_end_at=13,recover_at=15,animation='action_ground_special_'+'a'*24,range=32,radius=.45,cosine=.5,origin=[0,0,0],geometry_origin=[0,0,0],direction=[0,0,1],aim_revision=1,aim_locked=False,lock_at=11.5,age_ms=0,eligible_victim_ids=['6'],hit_policy='targeted',shape='targeted',special=True,target_required=True)
  visible={'5':dict(cell_id='0')}
  self.assertEqual(len(events(dict(action_events=[row]),visible,0)),1)
  for change in ({'eligible_victim_ids':['6','7']},{'target_required':False},{'shape':'unknown'},{'geometry_origin':[math.nan,0,0]},{'hit_policy':'cleave'}):
   self.assertEqual(events(dict(action_events=[dict(row,**change)]),visible,0),[])
  for shape in ('circle','cone'):
   area=dict(row,shape=shape,hit_policy='cleave',target_required=False,eligible_victim_ids=['6','7'])
   self.assertEqual(len(events(dict(action_events=[area]),visible,0)),1)
 def test_private_animation_delta_keeps_skeleton_and_geometry(self):
  import hashlib
  from tools.client.install_ground_actions import install
  with tempfile.TemporaryDirectory() as folder:
   root=Path(folder)/'root';source=Path(folder)/'source';source.mkdir();model=root/'runtime/assets/npc/models/body.json';model.parent.mkdir(parents=True)
   body={'bones':[{'name':'root'}],'geometry':'untouched','animation_library':{}};model.write_text(json.dumps(body))
   update=[{'model':str(model.relative_to(root)),'bones_sha256':hashlib.sha256(json.dumps(body['bones'],sort_keys=True,separators=(',',':')).encode()).hexdigest(),'animation_library':{'action_ground_creature':{'path':'animations/new.json'}}}]
   (source/'animation-updates.json').write_text(json.dumps(update));digest=hashlib.sha256((source/'animation-updates.json').read_bytes()).hexdigest();(source/'sha256.json').write_text(json.dumps({'animation-updates.json':digest}))
   self.assertEqual(install(root,source,True)['models'],1);self.assertEqual(json.loads(model.read_text()),body)
   install(root,source);changed=json.loads(model.read_text());self.assertEqual(changed['geometry'],'untouched');self.assertEqual(changed['bones'],body['bones']);self.assertIn('action_ground_creature',changed['animation_library'])
   changed['bones'][0]['name']='different';model.write_text(json.dumps(changed))
   with self.assertRaises(ValueError):install(root,source)
