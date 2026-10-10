#!/usr/bin/env python3
"""Export exact local NPC appearances and CDF wearable/customization definitions."""
import argparse,hashlib,json,struct
from pathlib import Path
from prepare_characters import CharacterImporter
from character_formats import child
from character_animations import export_character_animations,load_lat,resolve,decode_clip,version
from swg_formats import parse_iff,cstring
from npc_outfits import apply_outfit_variants,refresh_outfits
from npc_reference_repairs import resolve_cdf_mesh
from static_assets import StaticAssets
ROOT=Path(__file__).resolve().parents[2]

def cdf_attachments(imp,static,cdf,source_cdf,bones,template):
 """Original CDF rigid children follow named source skeleton joints."""
 attachments=[];names={bone['name'] for bone in bones}
 if source_cdf is None:return attachments
 for hobj in source_cdf.walk('HOBJ'):
  source,pos=cstring(hobj.data);bone,_=cstring(hobj.data,pos)
  try:
   if bone not in names:raise ValueError('Missing original CDF attachment bone '+bone)
   prior_failures=len(static.failures)
   pieces=static.resolve(source)
   if not pieces:raise ValueError('Original CDF attachment contains no meshes')
   visual_errors=[f for f in static.failures[prior_failures:] if f.get('phase') in ('material','component_child')]
   if visual_errors:raise ValueError('Incomplete original CDF attachment: '+repr(visual_errors))
   for piece in pieces:
    info=static.meshes[piece['mesh']]
    attachments.append({'template':source,'appearance':source,'bone':bone,'model':info['path'],
      'local_transform':[1,0,0,0,0,1,0,0,0,0,1,0],'local_transform_layout':'row_major_3x4',
      'source_cdf':cdf,'source_kind':'cdf_hobj','bounds_min':info['bounds_min'],'bounds_max':info['bounds_max']})
  except Exception as exc:imp.failures.append({'resource':source,'template':template,'phase':'cdf_attachment','error':str(exc)})
 imp.dependencies.update(static.dependencies)
 return attachments

def customization(root,tag):
 result={}
 for chunk in root.walk(tag):
  name,pos=cstring(chunk.data);result[name]=struct.unpack_from('<i',chunk.data,pos)[0]
 return result

def available_moods(node,selectors):
 data=version(node)
 if node.tag=='SSAT':
  variable=cstring(child(data,'INFO').data)[0];raw=child(data,'VAL ').data;count=struct.unpack_from('<H',raw)[0];pos=2;choices={}
  for _ in range(count):
   key,pos=cstring(raw,pos);index=struct.unpack_from('<H',raw,pos)[0];pos+=2;choices[key]=index
  if variable=='mood':return set(choices)
  default=child(data,'DFLT');index=choices.get(selectors.get(variable),struct.unpack('<H',default.data)[0] if default else 0);branches=[n for n in child(data,'ANMS').children if n.tag!='INFO']
  return available_moods(branches[index],selectors) if index<len(branches) else set()
 return set().union(*(available_moods(n,selectors) for n in data.children if n.children))

def main():
 ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--tre-dir',type=Path,default=ROOT/'runtime/asset_sources/active_tre');ap.add_argument('--out',type=Path,default=ROOT/'runtime/assets/ambient_npcs');ap.add_argument('--placements',type=Path,default=ROOT/'runtime/assets/ambient_npcs/placements.json');ap.add_argument('--limit',type=int,default=0);ap.add_argument('--merge',action='store_true',help='Retain existing exact descriptors and provenance while importing this request batch');ap.add_argument('--refresh-outfits',action='store_true',help='Refresh only Core3 outfit variants using existing NPC bodies and CDF descriptors');args=ap.parse_args()
 imp=CharacterImporter(args.tre_dir,args.out);placement_bytes=args.placements.read_bytes();placements=json.loads(placement_bytes);templates={}
 if args.refresh_outfits:
  print(json.dumps(refresh_outfits(imp,placements,args.placements,placement_bytes),indent=2));return
 for instance in placements['instances']:
  mood=instance.get('mood','neutral')
  # Native placements may use numeric mood IDs. This converter resolves the
  # named LAT selector only; numeric 0 means the default standing animation.
  templates.setdefault(instance['template'],set()).add(mood if isinstance(mood,str) else 'neutral')
 if args.limit:templates=dict(list(templates.items())[:args.limit])
 previous=json.loads((args.out/'catalog.json').read_text()) if args.merge and (args.out/'catalog.json').exists() else None
 catalog={'schema_version':1,'races':{},'failures':imp.failures,'warnings':['Exact source NPC SAT/CDF definitions, not player-race stand-ins.','Placement selection is the supplied Core3 export; NPCs are visual noninteractive presentation.','Source root motion is not applied. Unsupported wearables/appearance references are reported.']};body_cache={};clothing_cache={}
 static=StaticAssets(args.tre_dir,args.out);static.t=imp.t
 for template,moods in templates.items():
  shared=str(Path(template).parent/('shared_'+Path(template).name))
  try:
   props=imp.properties(shared);appearance=cstring(props['appearanceFilename'],1)[0];cdf=cstring(props['clientDataFile'],1)[0] if props.get('clientDataFile',b'')[:1]==b'\1' else '';source_cdf=None
   if previous:
    moods=moods|{mood for row in previous['races'].values() if row.get('appearance')==appearance for mood in row.get('mood_animations',{})}
   if cdf:
    try:source_cdf=parse_iff(imp.read(cdf))
    except KeyError as exc:imp.failures.append({'resource':cdf,'template':template,'phase':'client_data','error':str(exc)})
   sex='female' if Path(appearance).stem.endswith('_f') else 'male';race_key='npc_'+sex
   if appearance not in body_cache:
    model=imp.model(appearance);bones=model['bones'];names={b['name']:i for i,b in enumerate(bones)}
    try:model.update(export_character_animations(imp,appearance,race_key,bones,names))
    except Exception as exc:imp.failures.append({'resource':appearance,'phase':'animation_graph','error':str(exc)});model['animations']={};model['animation_library']={}
    model_path='models/'+hashlib.sha256(appearance.encode()).hexdigest()[:24]+'.json';body_cache[appearance]=(model,model_path)
   model,model_path=body_cache[appearance];bones=model['bones'];names={b['name']:i for i,b in enumerate(bones)}
   # Resolve requested NPC mood through its own original logical animation table.
   available=set()
   try:
    latraw=parse_iff(imp.read(appearance)).first('LATX').data;_,pos=cstring(latraw,2);lat,_=cstring(latraw,pos);_,table=load_lat(imp,lat);available=available_moods(table['loop_standing'],{'gender':'f' if sex=='female' else 'm'})
   except Exception:pass
   for mood in sorted(moods):
    if not mood or mood=='neutral' or mood not in available or 'mood_'+mood in model['animations']:continue
    try:
     latraw=parse_iff(imp.read(appearance)).first('LATX').data;_,pos=cstring(latraw,2);lat,_=cstring(latraw,pos);_,table=load_lat(imp,lat)
     leaves=resolve(table['loop_standing'],{'gender':'f' if sex=='female' else 'm','mood':mood});leaf=next(x for x in leaves if '_loc_' not in x['source'])
     clip=decode_clip(imp,leaf['source'],bones,names);clip.update(loop=True,logical='loop_standing',source_speed_scale=leaf.get('speed_scale',1));model['animations']['mood_'+mood]=clip
    except Exception as exc:imp.failures.append({'resource':appearance,'phase':'mood','mood':mood,'error':str(exc)})
   if previous and (args.out/model_path).exists():
    # Incremental source batches can share a body with existing NPCs whose
    # selected moods are absent from this batch. Retain their original clips.
    prior_body=json.loads((args.out/model_path).read_text())
    for field in ('animations','animation_library'):
     model[field]={**prior_body.get(field,{}),**model.get(field,{})}
   imp.write(model_path,model)
   skin=next((sf for part in model['parts'] for sf in part['mesh']['surfaces'] if '_body' in sf['shader'] and sf.get('palettes')),next(sf for part in model['parts'] for sf in part['mesh']['surfaces']))
   imp.skin_material={k:v for k,v in skin.items() if k not in ('vertices','normals','uv','indices','bones','weights','triangle_zones','blend_shapes')}
   outfit=[]
   if source_cdf:
    for index,wear in enumerate(source_cdf.walk('WEAR')):
     # A WEAR record may group several body-piece MESH chunks under one
     # authored customization scope (notably complete stormtrooper armor).
     for mesh in wear.walk('MESH'):
      source=cstring(mesh.data)[0]
      try:
       resolved,repair=resolve_cdf_mesh(imp,source,appearance,cdf);cache_key=(appearance,resolved,imp.skin_material['shader'])
       if cache_key not in clothing_cache:
        wearable=imp.model(resolved,bones,names);path='clothing/'+hashlib.sha256(repr(cache_key).encode()).hexdigest()[:24]+'.json';imp.write(path,wearable);clothing_cache[cache_key]=path
       row={'template':source,'appearance':resolved,'model':clothing_cache[cache_key],'customization':customization(wear,'WCSI'),'source_cdf':cdf,'source_wear_index':index}
       if repair:row['source_reference_repair']=repair
       outfit.append(row)
      except Exception as exc:imp.failures.append({'resource':source,'template':template,'phase':'wearable','error':str(exc)})
   body_customization=customization(source_cdf,'CSSI') if source_cdf else {}
   palettes={p['variable']:p for part in model['parts'] for sf in part['mesh']['surfaces'] for p in sf.get('palettes',[])}
   catalog['races'][template]={'template':template,'shared_template':shared,'appearance':appearance,'body':model_path,'source_cdf':cdf,'height_min':0.25,'height_max':3.0,'customizations':[],'palette_variables':palettes,'blend_shapes':sorted({b for part in model['parts'] for b in part['mesh'].get('blend_shapes',[])}),'hair':[],'default_hair':'','default_outfit':outfit,'profession_outfits':{},'bone_count':len(bones),'default_appearance':{'height':1.0,'customization':body_customization},'animation_states':sorted(model['animations']),'default_animation':'idle','mood_animations':{m:'mood_'+m for m in moods if m in available and 'mood_'+m in model['animations']},'unsupported_moods':sorted(m for m in moods if m and m not in available and m!='neutral')}
   catalog['races'][template]['rigid_equipment']=cdf_attachments(imp,static,cdf,source_cdf,bones,template)
   appearance_failures=[f for f in imp.failures if f.get('template')==template and f.get('phase') in ('wearable','client_data','cdf_attachment')]
   catalog['races'][template]['appearance_complete']=not appearance_failures
   if appearance_failures:catalog['races'][template]['appearance_failures']=appearance_failures
   print(template,len(bones),'bones',len(outfit),'wearables',flush=True)
  except Exception as exc:imp.failures.append({'resource':shared,'phase':'npc','error':repr(exc)});print('FAILED',shared,repr(exc),flush=True)
 outfit_report=apply_outfit_variants(imp,catalog,placements)
 catalog['provenance']={'core3_outfit_files_sha256':{key:value for key,value in placements['provenance']['files_sha256'].items() if '/mobile/outfits/' in key},'tre_directory':str(args.tre_dir.resolve()),'placement_manifest':str(args.placements.resolve()),'placement_sha256':hashlib.sha256(placement_bytes).hexdigest(),'dependencies':imp.dependencies}
 if previous:
  catalog['races']={**previous['races'],**catalog['races']}
  catalog['provenance']['dependencies']={**previous['provenance']['dependencies'],**imp.dependencies}
  catalog['provenance']['core3_outfit_files_sha256']={**previous['provenance'].get('core3_outfit_files_sha256',{}),**catalog['provenance']['core3_outfit_files_sha256']}
  catalog['provenance']['previous_batches']=previous['provenance'].get('previous_batches',[])+[{k:previous['provenance'][k] for k in ('placement_manifest','placement_sha256')}]
  shared_requested={str(Path(t).parent/('shared_'+Path(t).name)) for t in templates}
  catalog['failures']=[f for f in previous.get('failures',[]) if f.get('template') not in templates and f.get('resource') not in shared_requested and f.get('resource') not in body_cache and f.get('appearance_id') not in outfit_report['variants']]+catalog['failures']
  for k,v in previous.get('outfit_report',{}).get('variants',{}).items():catalog['outfit_report']['variants'].setdefault(k,v)
 catalog['statistics']={'outfit_variants':sum(bool(v['outfit']) for v in outfit_report['variants'].values()),'equipment_variants':len(outfit_report['variants']),'outfit_converted_items':outfit_report['converted_items'],'outfit_rigid_items':outfit_report['converted_rigid_items'],'unsupported_outfit_attachments':len(outfit_report['unsupported_attachments']),'outfit_conversion_failures':len(outfit_report['conversion_failures']),'requested_templates':len(templates),'exported_templates':sum('#outfit=' not in key and '#weapon=' not in key for key in catalog['races']),'exported_descriptors':len(catalog['races']),'unique_bodies':len(body_cache),'unique_wearables':len(clothing_cache),'failures':len(catalog['failures'])};imp.write('catalog.json',catalog);print(json.dumps(catalog['statistics'],indent=2),flush=True)
if __name__=='__main__':main()
