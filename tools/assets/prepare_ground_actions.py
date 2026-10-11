#!/usr/bin/env python3
"""Prepare original ground attack clips and server profile metadata from supplied media."""
import argparse,hashlib,json,sys
from pathlib import Path
from swg_formats import TreSet
from character_animations import load_lat,ground_action_bindings,decode_clip,animation_messages
ROOT=Path(__file__).resolve().parents[2]

def reviewed_catalog(local,lock):
 expected=hashlib.sha256(json.dumps(lock['templates'],sort_keys=True,separators=(',',':')).encode()).hexdigest()
 if lock['revision']!=expected:raise ValueError('Reviewed profile metadata checksum mismatch')
 matched=0
 for template,row in local.items():
  if template not in lock['templates']:continue
  for slot,profile in row['profiles'].items():
   if slot not in lock['templates'][template]['profiles']:continue
   if profile!=lock['templates'][template]['profiles'][slot]:raise ValueError('Original attack does not match reviewed profile: '+template+' '+slot)
   matched+=1
 if not matched:raise ValueError('No prepared models match the reviewed ground profiles')
 return lock['templates']

def main():
 global ROOT
 parser=argparse.ArgumentParser();parser.add_argument('--root',type=Path,default=ROOT);args=parser.parse_args();ROOT=args.root.resolve()
 tree=TreSet(ROOT/'runtime/asset_sources/active_tre');tables={};rows={};failures=[];skipped=[];converted=0
 catalogs=[ROOT/'runtime/assets'/p/'catalog.json' for p in ('combat_population/native_current','combat_population/mos_eisley_easy','combat_population/tatooine','combat_population/tatooine_entities','ambient_npcs')]
 for catalog in catalogs:
  if not catalog.exists():continue
  for template,record in json.loads(catalog.read_text()).get('races',{}).items():
   model_path=catalog.parent/record['body'];model=json.loads(model_path.read_text());graph=model.get('animation_graph',{});profiles={}
   for binding in graph.get('lat_bindings',[])[:1]:
    try:
     lat=binding['lat']
     if lat not in tables:tables[lat]=load_lat(tree,lat)[1]
     for slot,logical,leaf in ground_action_bindings(tables[lat],graph.get('selectors',{})):
      raw=tree.read(leaf['source']);clip=decode_clip(tree,leaf['source'],model['bones'],{b['name']:i for i,b in enumerate(model['bones'])});assert clip['tracks']
      duration=clip['length']/leaf['speed_scale']
      if not .1<=duration<=4:
       skipped.append({'template':template,'slot':slot,'source':leaf['source'],'sha256':clip['source_sha256'],'seconds':duration,'reason':'outside reviewed attack-duration bounds; retain native combat'});continue
      key='action_ground_'+slot;clip.update(loop=False,logical=logical,source_speed_scale=leaf['speed_scale'])
      encoded=json.dumps(clip,separators=(',',':'));relative='animations/'+hashlib.sha256(encoded.encode()).hexdigest()[:24]+'.json'
      (catalog.parent/relative).write_text(encoded);model.setdefault('animation_library',{})[key]={'path':relative,'source':leaf['source'],'logical':logical,'loop':False}
      markers=[v['seconds']/leaf['speed_scale'] for v in animation_messages(raw) if v['message'].lower().startswith('fire')]
      ranged=slot in ('pistol','rifle','carbine')
      if ranged and not markers:continue
      # Creature/weapon impact cues are often audio, not collision markers.
      # Conservative authored-duration-relative contact remains explicitly provisional.
      offset=min(markers) if ranged else duration*.35
      profiles[slot]={'animation':key,'duration':duration,'contact_offset':offset,'contact_window':.15 if ranged else min(.25,duration*.4),'windup':1.4 if ranged else 1.2,'lock_lead':.5,'recovery':1.4,'role':'ranged' if ranged else 'melee','hit_policy':'first_contact' if ranged else 'cleave','contact_timing':'authored_fire' if ranged else 'provisional_pose_review','source':leaf['source'],'source_sha256':clip['source_sha256'],'source_archive':Path(tree.entries[leaf['source']][0]).name}
      if 'selection_basis' in leaf:profiles[slot].update(logical=logical,selection_basis=leaf['selection_basis'])
      converted+=1
     model_path.write_text(json.dumps(model,separators=(',',':')))
    except Exception as error:failures.append({'template':template,'catalog':str(catalog.relative_to(ROOT)),'error':str(error)})
   if profiles:rows[template]={'family':record.get('appearance',''),'profiles':profiles}
 local_count=len(rows)
 lock=json.loads(Path(__file__).with_name('ground_action_profiles.json').read_text())
 rows=reviewed_catalog(rows,lock)
 result={'schema':2,'scope':lock['scope'],'templates':rows,'local_templates':local_count,'failures':failures,'skipped_profiles':skipped,'converted_clips':converted}
 result['revision']=hashlib.sha256(json.dumps(rows,sort_keys=True,separators=(',',':')).encode()).hexdigest()
 out=ROOT/'runtime/assets/combat_actions';out.mkdir(exist_ok=True);(out/'catalog.json').write_text(json.dumps(result,indent=2)+'\n')
 print(json.dumps({'templates':len(rows),'clips':converted,'failures':failures,'skipped_profiles':len(skipped),'output':str(out/'catalog.json')}))
 if failures:sys.exit(1)
if __name__=='__main__':main()
