#!/usr/bin/env python3
"""Stage the bounded integration and a separate private original-animation delta.

Does not deploy, restart services, launch clients or enable global rollout.
"""
import argparse,hashlib,json,shutil,sys,tarfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from tools.server.native_build_receipt import verify

def sha(p):
 with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def main():
 p=argparse.ArgumentParser();p.add_argument('destination',type=Path);a=p.parse_args();dest=a.destination.resolve()
 assert dest.is_relative_to(ROOT/'runtime/deploy') and not dest.exists(),'Use a new runtime/deploy directory'
 verify(ROOT);catalog=ROOT/'runtime/assets/combat_actions/catalog.json';data=json.loads(catalog.read_text());assert data['revision'] and not data['failures']
 dest.mkdir(parents=True)
 code=dest/'code';private=dest/'private-assets';manifest={}
 paths=list((ROOT/'server').rglob('*.py'))+list((ROOT/'server/combat').glob('*'))+list((ROOT/'server/patches').glob('*.patch'))
 paths+=[ROOT/p for p in ('server/ACTION_COMBAT_PROTOCOL.md','server/GROUND_COMBAT_INTEGRATION.md','tools/server/start-core3.sh','tools/server/native_build_receipt.py','tools/server/update_ground_combat_patch.py','tools/assets/prepare_ground_actions.py','tools/assets/character_animations.py','tools/client/install_ground_actions.py','runtime/server/native-build.json')]
 paths+=[ROOT/'vendor/Core3/MMOCoreORB/bin'/n for n in ('corecu','core3','core3client')]
 paths+=[ROOT/'client'/p for p in ('combat/action_clock.gd','combat/action_combat.gd','combat/action_pose.gd','combat/action_timeline.gd','combat/live_actor.gd','multiplayer/client_sync.gd','scripts/main.gd')]
 paths+=[ROOT/p for p in ('tests/ground_action_policy.cpp','tests/test_ground_action.py','tools/assets/test_ground_actions.py','client/tests/ground_action_smoke.gd','client/tests/action_pose_rig_smoke.gd')]
 paths+=[ROOT/'tools/assets/ground_action_profiles.json',ROOT/'tools/client/game_data_plan.py']
 for src in paths:
  if not src.is_file():continue
  rel=src.relative_to(ROOT);target=code/rel;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,target);manifest[str(rel)]=sha(target)
 updates=[];clips=set();models=set()
 for folder in ('combat_population/native_current','combat_population/mos_eisley_easy','combat_population/tatooine','combat_population/tatooine_entities','ambient_npcs'):
  src=ROOT/'runtime/assets'/folder/'catalog.json'
  if not src.exists():continue
  for row in json.loads(src.read_text()).get('races',{}).values():
   model=src.parent/row['body']
   if model in models:continue
   models.add(model);body=json.loads(model.read_text());entries={k:v for k,v in body.get('animation_library',{}).items() if k.startswith('action_ground_')}
   if not entries:continue
   updates.append({'model':str(model.relative_to(ROOT)),'bones_sha256':hashlib.sha256(json.dumps(body['bones'],sort_keys=True,separators=(',',':')).encode()).hexdigest(),'animation_library':entries})
   for value in entries.values():clips.add(src.parent/value['path'])
 for src in clips|{catalog}:
  target=private/src.relative_to(ROOT);target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,target)
 (private/'animation-updates.json').write_text(json.dumps(updates,separators=(',',':')))
 private_hashes={str(p.relative_to(private)):sha(p) for p in private.rglob('*') if p.is_file()}
 (private/'sha256.json').write_text(json.dumps(private_hashes,indent=2)+'\n')
 (code/'sha256.json').write_text(json.dumps(manifest,indent=2)+'\n')
 for folder,name in ((code,'ground-integration-code.tar.gz'),(private,'ground-animations-PRIVATE.tar.gz')):
  with tarfile.open(dest/name,'w:gz') as archive:archive.add(folder,arcname=folder.name)
 status={'kind':'ground_pve_integration','native_build_verified':True,'deployment_performed':False,'live_suite_performed':False,'xr_tested':False,'scope':data['scope'],'activation_environment':{'SWGXR_GROUND_ACTIONS':'mos_eisley','SWGXR_GROUND_ACTION_CATALOG':'/workspace/runtime/assets/combat_actions/catalog.json'},'catalog_revision':data['revision'],'templates_with_profiles':len(data['templates']),'converted_bindings':data['converted_clips'],'conversion_failures':len(data['failures']),'skipped_profiles':len(data['skipped_profiles']),'model_updates':len(updates),'animation_files':len(clips),'archives':{name:sha(dest/name) for name in ('ground-integration-code.tar.gz','ground-animations-PRIVATE.tar.gz')}}
 (dest/'package-status.json').write_text(json.dumps(status,indent=2)+'\n');print(json.dumps(status,indent=2))
if __name__=='__main__':main()
