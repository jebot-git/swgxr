"""Resolve native command animations through original standing ASH/LAT actions.

Metadata is deduplicated across rigs. Original clips stay local and retain their
full authored duration/speed. Unresolved aliases are reported, never fabricated.
"""
import hashlib,json,re
from pathlib import Path
from swg_formats import parse_iff,cstring
from character_formats import child
from character_animations import load_lat,resolve,decode_clip,animation_messages

def digest(value):return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(',',':')).encode()).hexdigest()
def revision(templates,specials=None,bindings=None):
 return digest(templates if specials is None else {'templates':templates,'special_profiles':specials,'special_bindings':bindings})
def command_animations(root):
 result={}
 for path in sorted((root/'vendor/Core3/MMOCoreORB/bin/scripts/commands').glob('*.lua')):
  text=re.sub(r'--[^\n]*','',path.read_text(errors='replace'))
  name=re.search(r'\bname\s*=\s*"([^"]+)"',text);anim=re.search(r'\banimation\s*=\s*"([^"]+)"',text)
  if not name or not anim:continue
  original=anim[1];alias=re.sub(r'_(?:light|medium|heavy)(?=_|$)','',original)
  aliases=[original,alias]
  if alias.startswith(('creature_','droid_')):aliases.append(alias.split('_',1)[1])
  if alias.startswith('force_'):
   aliases.append(re.sub(r'_\d.*$','',alias))
  result[name[1]]={'animation':original,'aliases':list(dict.fromkeys(aliases)),'source':str(path.relative_to(root)),'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
 return result

def standing_actions(tree,ash):
 result={}
 def walk(node,path=()):
  if node.tag=='STAT':
   info=child(node,'INFO')
   if info:path=(*path,cstring(info.data)[0])
  if node.tag=='ACTN':
   name,pos=cstring(node.data);logical,_=cstring(node.data,pos)
   if logical!='default':result.setdefault(path,{})[name]=logical
  for item in node.children:walk(item,path)
 walk(parse_iff(tree.read(ash)))
 return result

def compile_specials(root,tree,catalogs):
 commands=command_animations(root)
 if not commands:raise ValueError("Original Core3 command definitions are required for special attack preparation")
 profiles={};bindings={};missing={};failures=[];models=set();tables={};actions={};resolved={};clips={};exports={};written=set();converted=0
 state={'creature':None,'ranged':None,'unarmed':None,'onehand':'sword_1h','twohand':'sword_2h','polearm':'polearm','pistol':'pistol','rifle':'rifle','carbine':'carbine'}
 for catalog in catalogs:
  records=json.loads(catalog.read_text()).get('races',{})
  for record in records.values():
   path=catalog.parent/record['body']
   if path in models:continue
   models.add(path);model=json.loads(path.read_text());graph=model.get('animation_graph',{});lat_rows=graph.get('lat_bindings',[])
   if not lat_rows:continue
   family=record.get('appearance','');lat=lat_rows[0]['lat'];selectors=graph.get('selectors',{});bone_hash=digest(model['bones']);family_bindings={}
   if lat not in tables:
    ash,table=load_lat(tree,lat);tables[lat]=(ash,table)
    if ash not in actions:actions[ash]=standing_actions(tree,ash)
   ash,table=tables[lat];mapping=actions[ash]
   slots=[key.removeprefix('action_ground_') for key in model.get('animation_library',{}) if key.startswith('action_ground_') and not key.startswith('action_ground_special_')]
   for slot in slots:
    if slot not in state:continue
    paths=[('root',),('root','combat')]
    if state[slot]:paths += [('root',state[slot]),('root',state[slot],'combat')]
    aliases={}
    for entry in paths:aliases.update(mapping.get(entry,{}))
    for command,row in commands.items():
     cache=(lat,digest(selectors),slot,command)
     if cache not in resolved:
      selected=None
      for alias in row['aliases']:
       logical=aliases.get(alias,alias if alias in table else '')
       if logical not in table:continue
       leaves=resolve(table[logical],selectors);front=[v for v in leaves if v['source'].endswith('_front.ans')]
       if front:leaves=front
       unique={(v['source'],v['speed_scale']):v for v in leaves}
       if len(unique)==1:selected=(logical,next(iter(unique.values())));break
      resolved[cache]=selected
     selection=resolved[cache]
     if not selection:
      missing.setdefault(family,set()).add(slot+':'+command);continue
     logical,leaf=selection;source=leaf['source'];clip_key=(source,bone_hash)
     try:
      export_key=(clip_key,logical,leaf['speed_scale'],slot in ('ranged','rifle','pistol','carbine'))
      if export_key not in exports:
       if clip_key not in clips:
        raw=tree.read(source);clip=decode_clip(tree,source,model['bones'],{b['name']:i for i,b in enumerate(model['bones'])});assert clip['tracks'];clips[clip_key]=(clip,animation_messages(raw))
       decoded,messages=clips[clip_key];duration=decoded['length']/leaf['speed_scale']
       if not .1<=duration<=15:raise ValueError('Original special duration outside 0.1–15 seconds: '+str(duration))
       markers=[m['seconds']/leaf['speed_scale'] for m in messages if m['message'].lower().startswith('fire')]
       ranged=slot in ('ranged','rifle','pistol','carbine')
       profile={'duration':duration,'contact_offset':min(markers) if markers else duration*.35,'contact_window':.15 if ranged else min(.25,duration*.4),'windup':1.4 if ranged else 1.2,'lock_lead':.5,'recovery':1.4,'role':'ranged' if ranged else 'melee','hit_policy':'first_contact' if ranged else 'cleave','contact_timing':'authored_fire' if markers else 'provisional_pose_review','source':source,'source_sha256':decoded['source_sha256'],'source_archive':Path(tree.entries[source][0]).name,'logical':logical,'speed_scale':leaf['speed_scale']}
       identifier=digest(profile)[:24];key='action_ground_special_'+identifier;profile['animation']=key;profiles[identifier]=profile
       clip=dict(decoded,loop=False,logical=logical,source_speed_scale=leaf['speed_scale']);encoded=json.dumps(clip,separators=(',',':'));relative='animations/'+hashlib.sha256(encoded.encode()).hexdigest()[:24]+'.json'
       exports[export_key]=(identifier,key,profile,relative,encoded)
      identifier,key,profile,relative,encoded=exports[export_key];profiles[identifier]=profile;target=catalog.parent/relative
      if target not in written:target.write_text(encoded);written.add(target)
      model.setdefault('animation_library',{})[key]={'path':relative,'source':source,'logical':logical,'loop':False}
      family_bindings[slot+':'+command]=identifier;converted+=1
     except Exception as error:
      failures.append({'family':family,'slot':slot,'command':command,'source':source,'error':str(error)})
   if family_bindings:bindings.setdefault(family,{}).update(family_bindings)
   path.write_text(json.dumps(model,separators=(',',':')))
  print(json.dumps({'special_catalog':str(catalog.relative_to(root)),'unique_profiles':len(profiles),'model_bindings':converted}),flush=True)
 report={'commands':commands,'missing_aliases':{k:sorted(v) for k,v in missing.items()},'failures':failures,'model_bindings':converted}
 return profiles,bindings,report
