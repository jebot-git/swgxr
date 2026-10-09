#!/usr/bin/env python3
"""Export local Tatooine environment tables, original audio and placed emitters."""
import argparse, hashlib, io, json, struct, subprocess
from pathlib import Path
from PIL import Image
from swg_formats import TreSet, parse_iff, cstring
from character_formats import datatable, qmul, mirror
from static_assets import qrot
from terrain_formats import terrain
from interior_layout import expand_layouts, template_properties
from planet_config import PLANETS, origin_for, path_for
ROOT=Path(__file__).resolve().parents[2]

class EnvironmentImporter:
 def __init__(self,tre,out):
  self.t=TreSet(tre);self.out=out;self.dependencies={};self.sounds={};self.images={};self.failures=[];self.templates={};out.mkdir(parents=True,exist_ok=True)
 def read(self,path):
  path=path.replace('\\','/').lower();raw=self.t.read(path);self.dependencies[path]={'archive':self.t.entries[path][0].name,'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest()};return raw
 def image(self,path):
  if path in self.images:return self.images[path]
  raw=self.read(path);im=Image.open(io.BytesIO(raw)).convert('RGBA');relative='textures/'+hashlib.sha256(raw).hexdigest()[:24]+'.png';dest=self.out/relative;dest.parent.mkdir(exist_ok=True)
  if not dest.exists():im.save(dest)
  value={'source':path,'path':relative,'width':im.width,'height':im.height,'pixels':im};self.images[path]=value;return value
 def audio(self,path):
  raw=self.read(path);relative='audio/'+hashlib.sha256(raw).hexdigest()[:24]+'.ogg';dest=self.out/relative;dest.parent.mkdir(exist_ok=True)
  if not dest.exists():
   temporary=dest.with_suffix('.tmp.ogg');p=subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-i','pipe:0','-vn','-c:a','libvorbis','-q:a','5','-y',str(temporary)],input=raw,stderr=subprocess.PIPE)
   if p.returncode:raise ValueError(p.stderr.decode()[:300])
   temporary.replace(dest)
  return relative
 def sound(self,path):
  if path in self.sounds:return path
  try:
   root=parse_iff(self.read(path));version=root.first('0003');data=version.data;count=struct.unpack_from('<I',data)[0];p=4;sources=[]
   for _ in range(count):name,p=cstring(data,p);sources.append(name)
   tail=data[p:];assert len(tail)==112,('Unsupported SD2D numeric layout',len(tail))
   floats=lambda offset:list(struct.unpack_from('<2f',tail,offset));loops=list(struct.unpack_from('<2i',tail,16));volume=floats(72);delay=floats(24);distance=struct.unpack_from('<f',tail,108)[0]
   self.sounds[path]={'source':path,'samples':[self.audio(n) for n in sources],'sample_sources':sources,'spatial':root.tag=='SD3D','loop':loops[0]<0 and max(delay)<=0,'repeat':loops[0]<0,'loop_count_range':loops,'volume':sum(volume)/2,'volume_range':volume,'start_delay_seconds':floats(0),'delay_seconds':delay,'fade_in_seconds':floats(8),'fade_out_seconds':floats(32),'min_distance':max(1,distance),'max_distance':max(32,distance*8),'distance_policy':'Prototype 3D attenuation: SND final scalar interpreted as full-volume distance, max=8x/min32m; original rolloff unverified.','source_numeric_tail_hex':tail.hex(),'source_layout':'SD2D0003, including inherited SD3D definitions'}
   return path
  except Exception as exc:self.failures.append({'source':path,'phase':'sound','error':str(exc)});return ''
 def properties(self,path):
  return template_properties(self.read,path,self.templates)
 def shader(self,path):
  root=parse_iff(self.read(path));textures=[]
  for tx in root.walk('TXM '):
   source=cstring(tx.first('NAME').data)[0];image=self.image(source);textures.append({k:v for k,v in image.items() if k!='pixels'})
  return {'source':path,'textures':textures}

def snapshot(imp, planet="tatooine"):
 root=parse_iff(imp.read(f'snapshot/{planet}.ws'));names=root.first('OTNL').data[4:].split(b'\0');nodes={}
 for node in root.walk('NODE'):
  data=node.first('DATA').data;oid,parent,tid,cell=struct.unpack_from('<4I',data);nodes[oid]={'id':oid,'parent':parent,'template':names[tid].decode(),'cell':cell,'q':struct.unpack_from('<4f',data,16),'p':struct.unpack_from('<3f',data,32)}
 cache={}
 def resolve(oid):
  if oid in cache:return cache[oid]
  node=dict(nodes[oid])
  if node['parent']:
   parent=resolve(node['parent']);node['p']=[x+y for x,y in zip(qrot(parent['q'],node['p']),parent['p'])];node['q']=qmul(parent['q'],node['q'])
   if parent['template']=='object/cell/shared_cell.iff':node['cell_id']=str(parent['parent'])+':'+str(parent['cell']);node['source_cell_object_id']=parent['id']
   elif 'cell_id' in parent:node['cell_id']=parent['cell_id'];node['source_cell_object_id']=parent['source_cell_object_id']
  cache[oid]=node;return node
 return [resolve(oid) for oid in nodes]

def main():
 ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--planet',choices=PLANETS,default='tatooine');ap.add_argument('--tre-dir',type=Path,default=ROOT/'runtime/asset_sources/active_tre');ap.add_argument('--out',type=Path,default=None);ap.add_argument('--world',type=Path,default=None);ap.add_argument('--npc-placements',type=Path,default=None);args=ap.parse_args();args.out=args.out or path_for(args.planet,"environment");args.world=args.world or path_for(args.planet,"world")/"world.json";args.npc_placements=args.npc_placements or path_for(args.planet,"ambient")/"placements.json";imp=EnvironmentImporter(args.tre_dir,args.out)
 rows=datatable(imp.read(f'datatables/environment/{args.planet}.iff'));families={}
 for row in rows:
  family=row['Environment Family Name'];entry=families.setdefault(family,{'weather_variants':[]});entry['weather_variants'].append(row)
  if row['Weather Index']!=0:continue
  ramp=imp.image(row['Lighting Color Ramps (256x8 tga)']);sky=imp.image(row['Gradient Sky Texture (256x256 dds)']) if row['Gradient Sky Texture (256x256 dds)'] else None
  pixels=ramp['pixels'];norm=lambda color:[v/255 for v in color[:3]]
  entry['lighting_samples']=[{'ambient':norm(pixels.getpixel((x,0))),'sun':norm(pixels.getpixel((x,1))),'sky_top':norm(sky['pixels'].getpixel((x,0))) if sky else norm(pixels.getpixel((x,5))),'sky_horizon':norm(sky['pixels'].getpixel((x,sky['height']-1))) if sky else norm(pixels.getpixel((x,6)))} for x in range(pixels.width)]
  entry['lighting_source']={'ramp':ramp['source'],'path':ramp['path'],'rows_rgba':[[list(pixels.getpixel((x,y))) for x in range(pixels.width)] for y in range(pixels.height)],'mapping':'Presentation mapping: ambient=row0, sun=row1; source row semantics unverified. Sky top/horizon from actual gradient texture first/last row.','sky_texture':{k:v for k,v in sky.items() if k!='pixels'} if sky else None}
  for key,column in [('day_ambient','Day Ambient Sound 1 (2d .snd)'),('day_ambient_secondary','Day Ambient Sound 2 (2d .snd)'),('night_ambient','Night Ambient Sound 1 (2d .snd)'),('night_ambient_secondary','Night Ambient Sound 2 (2d .snd)'),('first_music','First Music (2d .snd)'),('sunrise_music','Sunrise Music (2d .snd)'),('sunset_music','Sunset Music (2d .snd)')]:entry[key]=imp.sound(row[column]) if row[column] else ''
  entry['fog']={'enabled':bool(row['Fog Enabled']),'minimum_density':row['Minimum Fog Density'],'maximum_density':row['Maximum Fog Density']}
 celestials=[]
 for node in parse_iff(imp.read(f'terrain/environment/{args.planet}.iff')).children[0].children:
  record={'tag':node.tag,'raw_hex':node.data.hex()}
  if node.tag in ('SUN ','SSUN','MOON','SMOO','CELS'):
   shader,p=cstring(node.data);size=struct.unpack_from('<f',node.data,p)[0];p+=4;glow,p=cstring(node.data,p)
   record.update(shader=imp.shader(shader) if shader else None,angular_size_source=size,glow_shader=imp.shader(glow) if glow else None,parameters=list(struct.unpack_from('<'+'f'*((len(node.data)-p)//4),node.data,p)))
  elif node.tag=='STAR':
   texture,p=cstring(node.data);image=imp.image(texture);record.update(texture={k:v for k,v in image.items() if k!='pixels'},count=struct.unpack_from('<I',node.data,p)[0])
  celestials.append(record)
 interior_soundscapes={};interior_table='datatables/interior/interior.iff'
 for index,row in enumerate(datatable(imp.read(interior_table))):
  entry={'pob_name':row['PobName'],'cell_name':row['Cell Name'],'source_table':interior_table,'source_row':index,'room_type':row['Room Type'],'source_values':row}
  for role,column in [('day_ambient','Day sound/ambient Sound (2d .snd)'),('night_ambient','Night sound/ambient Sound (2d .snd)'),('first_music','First Music (2d .snd)')]:entry[role]=imp.sound(row[column]) if row[column] else ''
  interior_soundscapes[row['PobName']+':'+row['Cell Name']]=entry
 nodes=snapshot(imp,args.planet);layout_nodes=expand_layouts(imp,nodes);nodes.extend(layout_nodes);origin=origin_for(args.planet);emitters=[]
 for node in nodes:
  if not node['template'].startswith(('object/soundobject/','object/building/')):continue
  try:
   cdf=imp.properties(node['template']).get('clientDataFile','')
   if not cdf:continue
   for sound in parse_iff(imp.read(cdf)).walk('ASND'):
    source=cstring(sound.data)[0];key=imp.sound(source)
    if key:
     item={'object_id':node['id'],'source_template':node['template'],'source_cdf':cdf,'position':mirror([node['p'][i]-origin[i] for i in range(3)]),'sound':key}
     if 'cell_id' in node:item.update(cell_id=node['cell_id'],source_cell_object_id=node['source_cell_object_id'])
     item.update({k:node[k] for k in ('source_layout','source_layout_index','building_object_id') if k in node})
     emitters.append(item)
  except Exception as exc:imp.failures.append({'source':node['template'],'phase':'sound_emitter','error':str(exc)})
 npc_source=None;npc_ambient_count=0
 if args.npc_placements.exists():
  raw_placements=args.npc_placements.read_bytes();npc_placements=json.loads(raw_placements);assert all(abs(a-b)<0.001 for a,b in zip(npc_placements['origin'],origin))
  npc_source={'path':str(args.npc_placements.resolve()),'sha256':hashlib.sha256(raw_placements).hexdigest()};template_sounds={}
  for placed in npc_placements['instances']:
   template=placed['template']
   if template not in template_sounds:
    template_sounds[template]=[]
    try:
     shared=str(Path(template).parent/('shared_'+Path(template).name));cdf=imp.properties(shared).get('clientDataFile','')
     if cdf:
      for sound in parse_iff(imp.read(cdf)).walk('ASND'):
       source=cstring(sound.data)[0];key=imp.sound(source)
       if key:template_sounds[template].append((cdf,key))
    except Exception as exc:imp.failures.append({'source':template,'phase':'npc_ambient','error':str(exc)})
   for cdf,key in template_sounds[template]:
    item={'object_id':'npc:'+placed['id'],'source_template':template,'source_cdf':cdf,'position':placed['position'],'sound':key,'source_kind':'Core3 visual NPC placement + original CDF ASND'}
    if placed.get('cell_id'):item['cell_id']=placed['cell_id']
    emitters.append(item);npc_ambient_count+=1
 coverage={'meshes_with_vertex_colors':0,'meshes_without_vertex_colors':0,'surfaces_with_vertex_colors':0,'surface_count':0,'vertex_count':0,'colored_vertex_count':0}
 if args.world.exists():
  world=json.loads(args.world.read_text())
  for descriptor in world['meshes'].values():
   model=json.loads((args.world.parent/descriptor['path']).read_text());has=False
   for surface in model['surfaces']:
    count=len(surface['vertices'])//3;colored=len(surface.get('colors',[]))==count*4;has|=colored;coverage['surface_count']+=1;coverage['vertex_count']+=count
    if colored:coverage['surfaces_with_vertex_colors']+=1;coverage['colored_vertex_count']+=count
   coverage['meshes_with_vertex_colors' if has else 'meshes_without_vertex_colors']+=1
 source_terrain=terrain(imp.read(f'terrain/{args.planet}.trn'));family_ids={family['id']:family['name'] for family in source_terrain['environment_families']};family_regions=[]
 def environment_regions(layer,parents=(),enabled=True):
  enabled=enabled and layer.get('enabled',True)
  if enabled:
   for affector in layer['affectors']:
    if affector['type']!='AENV' or not affector.get('enabled',True):continue
    family_regions.append({'family':family_ids[affector['family']],'source_layer':layer['name'],'source_coordinate_system':'SWG x,z','boundaries':layer['boundaries'],'filters':layer['filters'],'ancestor_constraints':[{'name':p['name'],'boundaries':p['boundaries'],'filters':p['filters']} for p in parents if p['boundaries'] or p['filters']],'affector':affector})
  for child_layer in layer['children']:environment_regions(child_layer,parents+(layer,),enabled)
 for layer in source_terrain['layers']:environment_regions(layer)
 output={'schema_version':1,'planet':args.planet,'origin':origin,'coordinate_system':'Godot Y-up, SWG Z mirrored; same Mos Eisley stage origin','cycle_seconds':7200,'cycle_source':'Prototype configurable duration; original day-length source not found','default_phase':0.25,'default_family':'moseisley' if args.planet=='tatooine' else next(iter(families)),'families':families,'family_regions':family_regions,'sounds':imp.sounds,'interior_soundscapes':interior_soundscapes,'interior_layout_nodes':len(layout_nodes),'emitters':emitters,'celestials':celestials,'vertex_color_coverage':coverage,'provenance':{'tre_directory':str(args.tre_dir.resolve()),'dependencies':imp.dependencies,'npc_placements':npc_source},'npc_ambient_emitters':npc_ambient_count,'failures':imp.failures,'warnings':['Source vertex colors are retained; their use as original baked lighting is not verified.','Original source shadows-enabled flags retained in table but runtime request disables dynamic shadows.','Lighting row role mapping and day duration are explicitly presentation choices; raw source values retained.','Original weather records exported; particle weather simulation is not implemented.']}
 dest=args.out/'environment.json';tmp=dest.with_suffix('.tmp');tmp.write_text(json.dumps(output,separators=(',',':')));tmp.replace(dest);print(json.dumps({'families':len(families),'sounds':len(imp.sounds),'emitters':len(emitters),'failures':len(imp.failures),'coverage':coverage,'output':str(dest)},indent=2))
if __name__=='__main__':main()
