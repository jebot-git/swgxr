#!/usr/bin/env python3
"""Extract full original Tatooine terrain rules and texture families for native streaming."""
import argparse,collections,hashlib,io,json
from pathlib import Path
from PIL import Image
from swg_formats import TreSet,parse_iff,cstring,refs
from terrain_formats import terrain
ROOT=Path(__file__).resolve().parents[2]
def main():
 ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--tre-dir',type=Path,default=ROOT/'runtime/assets/active_tre');ap.add_argument('--out',type=Path,default=ROOT/'runtime/assets/terrain');args=ap.parse_args();args.out.mkdir(parents=True,exist_ok=True)
 tre=TreSet(args.tre_dir);deps={};failures=[]
 def read(name):
  raw=tre.read(name);deps[name]={'archive':tre.entries[name][0].name,'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest()};return raw
 raw=read('terrain/tatooine.trn');data=terrain(raw);(args.out/'tatooine.trn').write_bytes(raw)
 data['water_regions']=[]
 def collect_water(layer):
  for boundary in layer['boundaries']:
   if boundary.get('water_enabled'):data['water_regions'].append(dict(boundary))
  for child in layer['children']:collect_water(child)
 for layer in data['layers']:collect_water(layer)
 data['water_shaders']={r['water_shader']:{'name':r['water_shader']} for r in data['water_regions']}
 for family in data['shader_families']+[{'shaders':list(data['water_shaders'].values())}]:
  for shader in family['shaders']:
   name=shader['name'];name=name if name.startswith('shader/') else 'shader/'+name;name=name if name.endswith('.sht') else name+'.sht';shader['path']=name
   try:
    root=parse_iff(read(name));textures=[]
    for tx in root.walk('TXM '):
     if not list(tx.walk('NAME')):
      textures.append({'tag':tx.first('DATA').data[:4][::-1].decode('ascii'),'dynamic':True});continue
     texname='/'.join(filter(None,cstring(tx.first('NAME').data)[0].lower().replace(chr(92),'/').split('/')));tag=tx.first('DATA').data[:4][::-1].decode('ascii');td=read(texname);rel='textures/'+hashlib.sha256(td).hexdigest()[:20]+'.png';out=args.out/rel;out.parent.mkdir(exist_ok=True)
     if not out.exists():Image.open(io.BytesIO(td)).convert('RGBA').save(out)
     textures.append({'tag':tag,'source':texname,'path':rel})
    shader['textures']=textures
   except Exception as e:failures.append({'resource':name,'error':str(e)})
 ramps={}
 def prepare_colors(layer):
  for rule in layer['affectors']:
   if rule['type'] not in ('ACRF','ACRH'):continue
   source=rule['ramp']
   if not source:continue
   try:
    if source not in ramps:
     image=Image.open(io.BytesIO(read(source))).convert('RGBA');w,h=image.size
     # Original color ramps are one row; retain every original texel.
     assert h==1,(source,image.size)
     ramps[source]={'size':[w,h],'colors':[[v/255 for v in image.getpixel((x,0))] for x in range(w)]}
   except Exception as e:failures.append({'resource':source,'error':str(e)})
  for child in layer['children']:prepare_colors(child)
 for layer in data['layers']:prepare_colors(layer)
 data['color_ramps']=ramps
 data['coordinate_system']='SWG ground coordinates x,z; heights SWG y; Godot mirrors z'
 data['height_evaluator']='Pinned Core3 procedural algorithm port; source parity tested separately'
 data['material_limitations']=['Material family blends reconstructed from original layer rules; original shader renderer and detail flora affectors are not fully reproduced.']
 data['unsupported_visual_rules']=dict(collections.Counter(n.tag for n in parse_iff(raw).walk() if n.tag in ['AFDN','AFDF','AFSC','AFSN','AFCN','ARCN']))
 data['provenance']={'source_revision':'Core3 403893d9b9f8e6fa712fbb3cb1fcd8f0fe45bb79','dependencies':deps};data['failures']=failures
 (args.out/'tatooine.json').write_text(json.dumps(data,separators=(',',':')))
 print(json.dumps({'manifest':str(args.out/'tatooine.json'),'extent':data['extent'],'fractals':len(data['fractals']),'shader_families':len(data['shader_families']),'root_layers':len(data['layers']),'failures':failures},indent=2))
if __name__=='__main__':main()
