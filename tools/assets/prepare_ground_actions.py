#!/usr/bin/env python3
"""Prepare original ground attack clips and server profile metadata from supplied media."""
import argparse,hashlib,json,sys
from pathlib import Path
from swg_formats import TreSet
from ground_catalogs import ground_catalogs,GROUND_PLANETS
from ground_specials import compile_specials,revision
from character_animations import load_lat,ground_action_bindings,decode_clip,animation_messages
ROOT=Path(__file__).resolve().parents[2]

def reviewed_catalog(local,lock):
 expected=revision(lock['templates'],lock.get('special_profiles'),lock.get('special_bindings'))
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
 parser=argparse.ArgumentParser();parser.add_argument('--root',type=Path,default=ROOT);parser.add_argument('--skip-base',action='store_true',help='Developer-only special audit after a complete base conversion');parser.add_argument('--update-profiles',action='store_true',help='Developer audit: pin newly converted original profile metadata');args=parser.parse_args();ROOT=args.root.resolve()
 tree=TreSet(ROOT/'runtime/asset_sources/active_tre');tables={};rows={};failures=[];skipped=[];converted=0
 catalogs=ground_catalogs(ROOT);models={};clips={};unconverted=[]
 if args.skip_base:rows=json.loads(Path(__file__).with_name('ground_action_profiles.json').read_text())['templates']
 for catalog in ([] if args.skip_base else catalogs):
  if not catalog.exists():continue
  for template,record in json.loads(catalog.read_text()).get('races',{}).items():
   model_path=catalog.parent/record['body']
   if model_path in models:
    profiles=models[model_path]
    if profiles:rows[template]={'family':record.get('appearance',''),'profiles':profiles}
    else:unconverted.append({'template':template,'family':record.get('appearance',''),'catalog':str(catalog.relative_to(ROOT)),'reason':'no unambiguous original basic-attack binding'})
    continue
   model=json.loads(model_path.read_text());graph=model.get('animation_graph',{});profiles={}
   bones_hash=hashlib.sha256(json.dumps(model['bones'],sort_keys=True,separators=(',',':')).encode()).hexdigest()
   for binding in graph.get('lat_bindings',[])[:1]:
    try:
     lat=binding['lat']
     if lat not in tables:tables[lat]=load_lat(tree,lat)[1]
     for slot,logical,leaf in ground_action_bindings(tables[lat],graph.get('selectors',{})):
      cache_key=(leaf['source'],bones_hash)
      if cache_key not in clips:
       raw=tree.read(leaf['source']);decoded=decode_clip(tree,leaf['source'],model['bones'],{b['name']:i for i,b in enumerate(model['bones'])});assert decoded['tracks'];clips[cache_key]=(decoded,animation_messages(raw))
      decoded,messages=clips[cache_key];clip=dict(decoded)
      duration=clip['length']/leaf['speed_scale']
      if not .1<=duration<=(15 if leaf.get('visual_fallback') else 4):
       skipped.append({'template':template,'slot':slot,'source':leaf['source'],'sha256':clip['source_sha256'],'seconds':duration,'reason':'outside reviewed attack-duration bounds; retain native combat'});continue
      key='action_ground_'+slot;clip.update(loop=False,logical=logical,source_speed_scale=leaf['speed_scale'])
      encoded=json.dumps(clip,separators=(',',':'));relative='animations/'+hashlib.sha256(encoded.encode()).hexdigest()[:24]+'.json'
      (catalog.parent/'animations').mkdir(exist_ok=True);(catalog.parent/relative).write_text(encoded);model.setdefault('animation_library',{})[key]={'path':relative,'source':leaf['source'],'logical':logical,'loop':False}
      markers=[v['seconds']/leaf['speed_scale'] for v in messages if v['message'].lower().startswith('fire')]
      ranged=slot in ('pistol','rifle','carbine','ranged')
      if ranged and not markers:continue
      # Creature/weapon impact cues are often audio, not collision markers.
      # Conservative authored-duration-relative contact remains explicitly provisional.
      offset=min(markers) if ranged else duration*.35
      profiles[slot]={'animation':key,'duration':duration,'contact_offset':offset,'contact_window':.15 if ranged else min(.25,duration*.4),'windup':1.4 if ranged else 1.2,'lock_lead':.5,'recovery':1.4,'role':'ranged' if ranged else 'melee','hit_policy':'first_contact' if ranged else 'cleave','contact_timing':'authored_fire' if ranged else 'provisional_pose_review','source':leaf['source'],'source_sha256':clip['source_sha256'],'source_archive':Path(tree.entries[leaf['source']][0]).name}
      if leaf.get('visual_fallback'):profiles[slot]['visual_fallback']=True
      if 'selection_basis' in leaf:profiles[slot].update(logical=logical,selection_basis=leaf['selection_basis'])
      converted+=1
     model_path.write_text(json.dumps(model,separators=(',',':')))
    except Exception as error:failures.append({'template':template,'catalog':str(catalog.relative_to(ROOT)),'error':str(error)})
   models[model_path]=profiles
   if profiles:rows[template]={'family':record.get('appearance',''),'profiles':profiles}
   else:unconverted.append({'template':template,'family':record.get('appearance',''),'catalog':str(catalog.relative_to(ROOT)),'reason':'no unambiguous original basic-attack binding'})
  print(json.dumps({'catalog':str(catalog.relative_to(ROOT)),'models':len(models),'templates':len(rows)}),flush=True)
 specials,special_bindings,special_audit=compile_specials(ROOT,tree,catalogs)
 local_families={r['family'] for r in rows.values()}
 local_count=len(rows)
 lock=json.loads(Path(__file__).with_name('ground_action_profiles.json').read_text())
 if args.update_profiles:
  reviewed_catalog({t:r for t,r in rows.items() if t in lock['templates']},lock)
  if failures or special_audit['failures']:
   audit=ROOT/'runtime/evidence/global-ground-conversion-failures.json';audit.parent.mkdir(parents=True,exist_ok=True);audit.write_text(json.dumps({'failures':failures,'skipped':skipped,'unconverted':unconverted},indent=2)+'\n')
   print(json.dumps({'failures':failures}),flush=True);raise ValueError('Cannot pin profiles with conversion failures')
  lock=dict(schema=2,special_profiles=specials,special_bindings=special_bindings,scope={'zones':list(GROUND_PLANETS),'basis':'native ground NPCs; player targets; excludes pets, PvP and JtL','global_enabled':True},templates=rows,revision=revision(rows,specials,special_bindings),description='Original rig-bound ground PvE basic and special attack profiles; explicit pose fallbacks recorded; proprietary animation media is prepared locally.')
  Path(__file__).with_name('ground_action_profiles.json').write_text(json.dumps(lock,separators=(',',':'))+'\n')
 else:
  rows=reviewed_catalog(rows,lock)
  for family in local_families:
   if special_bindings.get(family,{})!=lock.get('special_bindings',{}).get(family,{}):raise ValueError('Prepared special mappings differ from pinned metadata: '+family)
  for identifier,profile in specials.items():
   if profile!=lock.get('special_profiles',{}).get(identifier):raise ValueError('Prepared special profile differs from pinned metadata: '+identifier)
 result={'schema':2,'scope':lock['scope'],'templates':rows,'local_templates':local_count,'failures':failures,'skipped_profiles':skipped,'converted_clips':converted,'unconverted_templates':unconverted,'catalogs':[str(p.relative_to(ROOT)) for p in catalogs],'families':len({r['family'] for r in rows.values()}),'special_profiles':lock.get('special_profiles',{}),'special_bindings':lock.get('special_bindings',{}),'special_audit':{'model_bindings':special_audit['model_bindings'],'failures':len(special_audit['failures']),'unresolved_aliases':sum(len(v) for v in special_audit['missing_aliases'].values()),'report':'special-audit.json'}}
 result['revision']=revision(rows,lock.get('special_profiles'),lock.get('special_bindings'))
 out=ROOT/'runtime/assets/combat_actions';out.mkdir(exist_ok=True);(out/'special-audit.json').write_text(json.dumps(special_audit,indent=2)+'\n');(out/'catalog.json').write_text(json.dumps(result,indent=2)+'\n')
 print(json.dumps({'templates':len(rows),'clips':converted,'failures':failures,'skipped_profiles':len(skipped),'unconverted_templates':len(unconverted),'families':result['families'],'output':str(out/'catalog.json')}))
 if failures or special_audit['failures']:sys.exit(1)
if __name__=='__main__':main()
