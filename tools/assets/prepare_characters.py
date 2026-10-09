#!/usr/bin/env python3
"""Prepare authentic skinned character meshes from the local pre-CU TRE set."""
from pathlib import Path
import argparse,hashlib,io,json,struct,re
from PIL import Image
from swg_formats import TreSet,parse_iff,cstring
from character_formats import strings,child,array,datatable,qmul,mirror,mirror_quaternion,unpack_quaternion
from character_animations import export_character_animations
from facial_materials import material_extensions,renderer,supported_variables
ROOT=Path(__file__).resolve().parents[2]

class CharacterImporter:
 def __init__(self,tre,out):
  self.t=TreSet(tre);self.out=Path(out);self.out.mkdir(parents=True,exist_ok=True);self.dependencies={};self.materials={};self.failures=[]
 def read(self,path):
  path=path.lower().replace('\\','/');d=self.t.read(path)
  self.dependencies[path]={'archive':self.t.entries[path][0].name,'bytes':len(d),'sha256':hashlib.sha256(d).hexdigest()}
  return d
 def write(self,relative,data):
  path=self.out/relative;path.parent.mkdir(parents=True,exist_ok=True);tmp=path.with_suffix(path.suffix+'.tmp');tmp.write_text(json.dumps(data,separators=(',',':')));tmp.replace(path)
 def properties(self,path):
  root=parse_iff(self.read(path));result={}
  for n in root.walk('XXXX'):
   if b'\0' not in n.data:continue
   key,pos=cstring(n.data)
   result[key]=n.data[pos:]
  return result
 def appearance(self,path):
  p=self.properties(path);v=p.get('appearanceFilename',b'')
  if v[:1]==b'\1':return cstring(v,1)[0]
  raise ValueError('No appearance '+path)
 def shader(self,path):
  if path.startswith('shader/skin_') and hasattr(self,'skin_material'):return {**self.skin_material,'shader':path,'resolved_skin_shader':self.skin_material['shader']}
  if path in self.materials:return self.materials[path]
  r=parse_iff(self.read(path));candidates=[];palettes=[]
  for tx in r.walk('TXM '):
   name=cstring(tx.first('NAME').data)[0].replace('\\','/');tag=tx.first('DATA').data[:4]
   if tag==b'NIAM':candidates.insert(0,name)
   elif tag not in (b'LMRN',b'PUKL',b'CEPS'):candidates.append(name)
  if not candidates:raise ValueError('No diffuse texture '+path)
  tex=candidates[0];d=self.read(tex);rel='textures/'+hashlib.sha256(d).hexdigest()[:20]+'.png';dest=self.out/rel;dest.parent.mkdir(exist_ok=True)
  if not dest.exists():Image.open(io.BytesIO(d)).convert('RGBA').save(dest)
  for p in r.walk('PAL '):
   var,pos=cstring(p.data);private=bool(p.data[pos]);tag=p.data[pos+1:pos+5].decode('ascii')[::-1];palette,pos=cstring(p.data,pos+5);default=struct.unpack_from('<i',p.data,pos)[0]
   raw=self.read(palette);assert raw[:4]==b'RIFF';count=struct.unpack_from('<H',raw,22)[0];colors=[[a/255,b/255,c/255,d/255] for a,b,c,d in array(raw[24:24+4*count],'4B')]
   palettes.append({'variable':var,'variable_path':('/private/' if private else '/shared_owner/')+var,'tag':tag,'palette':palette,'colors':colors,'default':default,'min':0,'max':count-1})
  effects=[cstring(n.data)[0].replace('\\','/').lower() for n in r.walk('NAME') if n.data.rstrip(b'\0').lower().endswith(b'.eft')]
  alpha_evidence=[]
  for effect in effects:
   er=parse_iff(self.read(effect))
   for impl in er.walk('IMPL'):
    version=impl.children[0];idata=child(version,'DATA');first_pass=child(version,'PASS');pdata=first_pass.children[0].first('DATA').data if first_pass else b''
    sort_tag=idata.data[1:5].decode('ascii')[::-1] if idata and len(idata.data)>=5 else ''
    # PASS0009 offset11 is alpha-test enabled; the effect's ALPH sort
    # bucket independently signals transparency even on programmable passes.
    alpha_test=bool(pdata[11]) if first_pass and first_pass.children[0].tag=='0009' and len(pdata)==56 else False
    alpha_evidence.append({'effect':effect,'implementation':version.tag,'sort_tag':sort_tag,'alpha_test':alpha_test})
  mat={'texture':rel,'shader':path,'palettes':palettes,'alpha':any(e['sort_tag']=='ALPH' or e['alpha_test'] for e in alpha_evidence),'alpha_source':alpha_evidence}
  mat=material_extensions(self,r,mat)
  self.materials[path]=mat;return mat
 def skeleton(self,sat):
  r=parse_iff(self.read(sat));bones=[];names={};d=r.first('SKTI').data;pos=0
  while pos<len(d):
   skt,pos=cstring(d,pos);attach,pos=cstring(d,pos)
   node=parse_iff(self.read(skt)).first('SKTM');bn=strings(node.first('NAME').data);parents=[x[0] for x in array(node.first('PRNT').data,'i')]
   translations=array(node.first('BPTR').data,'3f');pres=array(node.first('RPRE').data,'4f');posts=array(node.first('RPST').data,'4f');rests=array(node.first('BPRO').data,'4f');offset=len(bones)
   for i,name in enumerate(bn):
    name=name.lower();assert name not in names,(skt,name)
    parent=offset+parents[i] if parents[i]>=0 else names.get(attach.lower(),-1)
    names[name]=len(bones)
    bones.append({'name':name,'parent':parent,'rest_position':mirror(translations[i]),'rest_rotation':mirror_quaternion(qmul(posts[i],qmul(rests[i],pres[i]))),'source_skeleton':skt,'source_bind_rotation':rests[i],'source_pre_rotation':pres[i],'source_post_rotation':posts[i]})
  return bones,names
 def mesh(self,path,bones,names):
  if path.endswith('.lmg'):path=cstring(parse_iff(self.read(path)).first('NAME').data)[0]
  r=parse_iff(self.read(path));version=r.children[0];assert version.tag in ('0003','0004')
  posns=[mirror(v) for v in array(child(version,'POSN').data,'3f')];norms=[mirror(v) for v in array(child(version,'NORM').data,'3f')]
  joint_names=[s.lower() for s in strings(child(version,'XFNM').data)];joint_map=[names[n] for n in joint_names]
  counts=[x[0] for x in array(child(version,'TWHD').data,'I')];weights=array(child(version,'TWDT').data,'If');vertex_weights=[];offset=0;virtual_skin_bones=[];virtual_skin_audit=[]
  for vertex_index,count in enumerate(counts):
   selected=sorted(weights[offset:offset+count],key=lambda w:w[1],reverse=True);offset+=count
   total=sum(w for _,w in selected);assert total>0
   if len(selected)>8:
    # Equal-weight source influences can share one exact affine mean matrix.
    # Keep all differently weighted joints separately, including multiple
    # dominant joints (acklay); never drop or renormalize away source weights.
    groups={}
    for j,w in selected:groups.setdefault(w,[]).append(j)
    baseline,group=max(groups.items(),key=lambda pair:len(pair[1]))
    assert len(selected)-len(group)+1<=8,(path,'unsupported dense weight pattern',len(selected))
    source_bones=sorted(joint_map[j] for j in group);assert len(set(source_bones))==len(source_bones)
    virtual_name='swg_dense_skin_average_'+hashlib.sha256(repr(source_bones).encode()).hexdigest()[:12]
    if virtual_name not in names:
     names[virtual_name]=len(bones);bones.append({'name':virtual_name,'parent':-1,'rest_position':[0,0,0],'rest_rotation':[0,0,0,1],'source_skeleton':'derived exact affine average of source joint matrices'})
    virtual=names[virtual_name]
    record={'bone':virtual,'source_bones':source_bones}
    if record not in virtual_skin_bones:virtual_skin_bones.append(record)
    virtual_skin_audit.append({'source_mesh':path,'source_vertex':vertex_index,'position':posns[vertex_index],'bones':[joint_map[j] for j,w in selected],'weights':[w/total for j,w in selected]})
    selected=[(joint_map[j],w/total) for j,w in selected if j not in group]+[(virtual,len(source_bones)*baseline/total)]
   else:selected=[(joint_map[j],w/total) for j,w in selected]
   selected.extend([(0,0)]*(8-len(selected)));vertex_weights.append(selected)
  blends={}
  for bl in version.walk('BLT '):
   name=cstring(bl.first('INFO').data,8)[0];bp=child(bl,'POSN');bn=child(bl,'NORM')
   blends[name]={'positions':{i:mirror((x,y,z)) for i,x,y,z in array(bp.data,'I3f')} if bp else {},'normals':{i:mirror((x,y,z)) for i,x,y,z in array(bn.data,'I3f')} if bn else {}}
  ozn=child(version,'OZN ');zone_names=strings(ozn.data) if ozn else [];ozc=child(version,'OZC ');zone_combos=[]
  if ozc:
   d=ozc.data;p=0
   while p<len(d):
    count=struct.unpack_from('<h',d,p)[0];p+=2;indices=struct.unpack_from('<'+'h'*count,d,p);p+=2*count;zone_combos.append([zone_names[j] for j in indices])
  zto=child(version,'ZTO ');occludes=[zone_names[v[0]] for v in array(zto.data,'h')] if zto else []
  surfaces=[]
  for ps in version.children:
   if ps.tag!='PSDT':continue
   shader=cstring(ps.first('NAME').data)[0];pidx=[x[0] for x in array(ps.first('PIDX').data[4:],'I')];nidx=[x[0] for x in array(ps.first('NIDX').data,'I')];n=len(pidx)
   tc=child(ps,'TXCI');uv=[]
   if tc:
    dimensions=[x[0] for x in array(tc.data,'I')][1:];tcdata=ps.first('TCSF').children[0].data
    uv=[c for vals in array(tcdata,'f'*dimensions[0]) for c in vals[:2]]
   indices=[];triangle_zones=[]
   for prim in ps.first('PRIM').children:
    if prim.tag=='ITL ':
     for a,b,c in array(prim.data[4:],'3I'):indices.extend([a,b,c]);triangle_zones.append([])
    elif prim.tag=='OITL':
     for zone,a,b,c in array(prim.data[4:],'h3I'):indices.extend([a,b,c]);triangle_zones.append(zone_combos[zone] if zone>=0 else [])
    elif prim.tag!='INFO':raise ValueError('Unsupported primitive '+prim.tag)
   surface={'vertices':[c for i in pidx for c in posns[i]],'normals':[c for i in nidx for c in norms[i]],'uv':uv,'indices':indices,'bones':[j for i in pidx for j,w in vertex_weights[i]],'weights':[w for i in pidx for j,w in vertex_weights[i]],'triangle_zones':triangle_zones,**self.shader(shader),'blend_shapes':{}}
   for name,blend in blends.items():
    surface['blend_shapes'][name]={'vertices':[c for i in pidx for c in blend['positions'].get(i,(0,0,0))],'normals':[c for i in nidx for c in blend['normals'].get(i,(0,0,0))]}
   assert len(surface['vertices'])==3*n and len(surface['bones'])==8*n and max(indices)<n
   surfaces.append(surface)
  for trt in version.walk('TRT '):
   renderer_path,p=cstring(trt.data);definition=renderer(self,renderer_path);count=struct.unpack_from('<I',trt.data,p)[0];p+=4
   for _ in range(count):
    si=struct.unpack_from('<I',trt.data,p)[0];tag=trt.data[p+4:p+8].decode('ascii')[::-1];p+=8
    surfaces[si]['texture_renderer']=renderer_path;surfaces[si]['texture_renderer_definition']=definition
    for layer in definition['layers']:
     if 'palette' in layer:surfaces[si]['palettes']=[*surfaces[si]['palettes'],{**layer['palette'],'source_renderer':renderer_path}]
  return {'surfaces':surfaces,'blend_shapes':list(blends),'bone_count':len(bones),'source':path,'virtual_skin_bones':virtual_skin_bones,'virtual_skin_audit':virtual_skin_audit,'occludes':occludes,'occlusion_layer':struct.unpack_from('<h',version.first('INFO').data,42)[0]}
 def animation(self,path,bones,names):
  r=parse_iff(self.read(path));assert r.tag in ('KFAT','CKAT');compressed=r.tag=='CKAT'
  fps,last_frame,_,_,_,_,_=struct.unpack('<f6h' if compressed else '<f6i',r.first('INFO').data)
  if compressed:
   rotations=[[(frame,*unpack_quaternion(packed,n.data[2:5])) for frame,packed in array(n.data[5:],'hI')] for n in r.first('AROT').children]
   static_rot=[unpack_quaternion(packed,(x,y,z)) for x,y,z,packed in array(r.first('SROT').data,'3BI')]
   translations=[array(n.data[2:],'hf') for n in r.first('ATRN').children]
  else:
   rotations=[array(n.data[4:],'I4f') for n in r.first('AROT').children]
   static_rot=array(r.first('SROT').data,'4f')
   translations=[array(n.data[4:],'If') for n in r.first('ATRN').children]
  static_trans=[v[0] for v in array(r.first('STRN').data,'f')];tracks=[]
  def sample(keys,frame):
   for j in range(1,len(keys)):
    if frame<=keys[j][0]:
     a,b=keys[j-1],keys[j];return a[1]+(b[1]-a[1])*(frame-a[0])/(b[0]-a[0]) if b[0]!=a[0] else b[1]
   return keys[-1][1]
  for n in r.first('XFRM').children:
   name,p=cstring(n.data);name=name.lower()
   if name not in names:continue
   animated,ri,mask,xi,yi,zi=struct.unpack_from('<BhB3h' if compressed else '<BiI3i',n.data,p);bi=names[name];bone=bones[bi]
   qr=rotations[ri] if animated else [(0,*static_rot[ri])]
   qkeys=[[frame/fps,*mirror_quaternion(qmul(bone['source_post_rotation'],qmul(q,qmul(bone['source_bind_rotation'],bone['source_pre_rotation']))))] for frame,*q in qr]
   channels=[translations[index] if mask&(8<<axis) else [(0,static_trans[index])] for axis,index in enumerate((xi,yi,zi))]
   times=sorted(set(frame for keys in channels for frame,_ in keys));pkeys=[]
   for frame in times:
    delta=mirror([sample(keys,frame) for keys in channels]);pkeys.append([frame/fps,*[bone['rest_position'][j]+delta[j] for j in range(3)]])
   tracks.append({'bone':bi,'name':name,'rotations':qkeys,'positions':pkeys})
  return {'fps':fps,'length':last_frame/fps,'source':path,'tracks':tracks,'root_motion':'ignored; gameplay controller drives translation'}
 def wearable(self,template,race,bones,names):
  appearance=self.appearance(template);stem=Path(appearance).stem
  sex='f' if race.endswith('_female') else 'm';stem=re.sub(r'_[mf]$','_'+sex,stem)
  prefix='wke_' if race.startswith('wookiee_') else 'ith_' if race.startswith('ithorian_') else ''
  candidates=['appearance/'+prefix+stem+'.sat','appearance/'+stem+'.sat',appearance]
  appearance=next(x for x in candidates if x in self.t.entries)
  model=self.model(appearance,bones,names);path='clothing/'+race+'/'+Path(template).stem+'.json';self.write(path,model)
  return {'template':template.replace('/shared_','/'),'shared_template':template,'appearance':appearance,'model':path}
 def model(self,appearance,bones=None,names=None):
  r=parse_iff(self.read(appearance))
  if bones is None:bones,names=self.skeleton(appearance)
  paths=strings(r.first('MSGN').data) if appearance.endswith('.sat') else [appearance]
  parts=[]
  for path in paths:
   mesh=self.mesh(path,bones,names);stem=Path(path).stem
   part_id=next((k for k in ['head','arms','hands','body','feet','legs'] if stem.endswith('_'+k)),stem)
   parts.append({'id':part_id,'mesh':mesh})
  return {'schema_version':1,'coordinate_system':'Godot Y-up, original SWG Z mirrored','appearance':appearance,'bones':bones,'parts':parts,'virtual_skin_bones':[record for part in parts for record in part['mesh'].get('virtual_skin_bones',[])],'virtual_skin_audit':[record for part in parts for record in part['mesh'].get('virtual_skin_audit',[])]}

def main():
 ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--tre-dir',type=Path,default=ROOT/'runtime/asset_sources/active_tre');ap.add_argument('--out',type=Path,default=ROOT/'runtime/assets/characters');ap.add_argument('--races',nargs='*',default=[species+'_'+sex for species in ['human','zabrak','bothan','moncal','rodian','trandoshan','twilek','wookiee','ithorian','sullustan'] for sex in ['male','female']]);ap.add_argument('--hair-limit',type=int,default=-1)
 args=ap.parse_args();imp=CharacterImporter(args.tre_dir,args.out);rows=datatable(imp.read('datatables/customization/customization_data.iff'));hair_root=parse_iff(imp.read('creation/default_pc_hairstyles.iff'));hairs={}
 for h in hair_root.walk('PTMP'):
  template=cstring(h.first('NAME').data)[0];hairs[template]={'default':cstring(child(h,'DEFA').data)[0] if child(h,'DEFA') else '', 'templates':strings(child(h,'ITMS').data) if child(h,'ITMS') else []}
 equipment={}
 for key,source in [('default','creation/default_pc_equipment.iff')]+[(p,'creation/profession_defaults_'+p+'.iff') for p in ['combat_brawler','combat_marksman','crafting_artisan','outdoors_scout','science_medic','social_entertainer']]:
  equipment[key]={}
  for node in parse_iff(imp.read(source)).walk('PTMP'):
   equipment[key][cstring(node.first('NAME').data)[0]]=[cstring(n.data,4)[0] for n in node.children if n.tag=='ITEM']
 catalog={'schema_version':1,'races':{},'failures':imp.failures,'warnings':['Original idle and walk clips are decoded; original root motion is not applied.','Character material colors, texture selectors, normal maps and authored facial layers are reproduced; original lighting multipass/specular effects are approximated by Godot shading.']}
 for race in args.races:
  template='object/creature/player/shared_'+race+'.iff'
  try:
   props=imp.properties(template);appearance=cstring(props['appearanceFilename'],1)[0];model=imp.model(appearance);bones=model['bones'];names={b['name']:i for i,b in enumerate(bones)}
   model.update(export_character_animations(imp,appearance,race,bones,names))
   path='models/'+race+'.json';imp.write(path,model)
   imp.skin_material=next((sf for part in model['parts'] for sf in part['mesh']['surfaces'] if '_body' in sf['shader'] and sf['palettes']), next(sf for part in model['parts'] for sf in part['mesh']['surfaces']))
   imp.skin_material={k:v for k,v in imp.skin_material.items() if k not in ('vertices','normals','uv','indices','bones','weights','triangle_zones','blend_shapes')}
   outfits={};wearables={}
   for key,byrace in equipment.items():
    outfits[key]=[]
    for wearable in byrace.get(template,[]):
     if not wearable.startswith('object/tangible/wearables/'):continue
     try:
      if wearable not in wearables:wearables[wearable]=imp.wearable(wearable,race,bones,names)
      outfits[key].append(wearables[wearable])
     except Exception as e:imp.failures.append({'resource':wearable,'race':race,'error':repr(e)})
   scale=props.get('scale',b'');bounds=struct.unpack_from('<2f',scale,2) if scale[:2]==b'\3 ' else (1,1)
   custom=[];available_blends=set();palette_vars={};material_variables=set()
   for part in model['parts']:
    available_blends.update(part['mesh']['blend_shapes'])
    for sf in part['mesh']['surfaces']:
     material_variables.update(supported_variables(sf))
     for p in sf['palettes']:palette_vars.setdefault(p['variable'],p)
   for row in rows:
    if row['SPECIES_GENDER']!=race:continue
    variables=[s for s in row['VARIABLES'].split(',') if s];supported=bool(row['IS_SCALE']) or all(v in available_blends or v in material_variables for v in variables)
    custom.append({'name':row['CUSTOMIZATION_NAME'],'group':row['CUSTOMIZATION_GROUP'],'type':row['TYPE'],'variables':variables,'is_scale':bool(row['IS_SCALE']),'reverse':bool(row['REVERSE']),'discrete':bool(row['DISCRETE']),'color_linked':row['COLOR_LINKED'],'supported':supported,'source':row})
   hair=[]
   for htemplate in hairs.get(template,{}).get('templates',[])[:args.hair_limit if args.hair_limit>=0 else None]:
    try:
     happ=imp.appearance(htemplate);hmodel=imp.model(happ,bones,names);hpath='hair/'+race+'/'+Path(htemplate).stem+'.json';imp.write(hpath,hmodel)
     hair_palettes={p['variable']:p for part in hmodel['parts'] for surface in part['mesh']['surfaces'] for p in surface['palettes']}
     hair.append({'palette_variables':hair_palettes,'template':htemplate.replace('/shared_','/'),'shared_template':htemplate,'appearance':happ,'model':hpath})
    except Exception as e:imp.failures.append({'resource':htemplate,'error':repr(e)})
   catalog['races'][race]={'template':template.replace('/shared_','/'),'shared_template':template,'appearance':appearance,'body':path,'height_min':bounds[0],'height_max':bounds[1],'customizations':custom,'palette_variables':palette_vars,'blend_shapes':sorted(available_blends),'hair':hair,'source_hair_templates':hairs.get(template,{}).get('templates',[]),'default_hair':hairs.get(template,{}).get('default',''),'bone_count':len(bones),'default_outfit':outfits.pop('default',[]),'profession_outfits':outfits}
   print(race,len(bones),'bones',sum(len(p['mesh']['surfaces']) for p in model['parts']),'surfaces',len(available_blends),'blends',len(hair),'hair',flush=True)
  except Exception as e:imp.failures.append({'resource':template,'error':repr(e)});print('FAILED',race,repr(e),flush=True)
 catalog['provenance']={'tre_directory':str(args.tre_dir.resolve()),'dependencies':imp.dependencies};imp.write('catalog.json',catalog)
 print('catalog',args.out/'catalog.json','races',len(catalog['races']),'failures',len(imp.failures),flush=True)
if __name__=='__main__':main()
