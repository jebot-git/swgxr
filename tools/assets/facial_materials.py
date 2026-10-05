"""Convert original SWG character material selectors and baked texture recipes.

The implementation reads user-supplied BTRT/SHT assets. It does not bundle their
textures or shader source. Color arithmetic is evaluated by our Godot shader.
"""
import hashlib, io, struct
from PIL import Image
from swg_formats import parse_iff,cstring
from character_formats import child,array,strings


def texture(imp,path):
 path=path.replace('\\','/').lower();data=imp.read(path)
 rel='textures/'+hashlib.sha256(data).hexdigest()[:20]+'.png';dest=imp.out/rel
 dest.parent.mkdir(exist_ok=True)
 if not dest.exists():Image.open(io.BytesIO(data)).convert('RGBA').save(dest)
 return rel


def palette(imp,path,variable,private,tag='MAIN',default=0):
 path=path.replace('\\','/').lower();data=imp.read(path)
 assert data[:4]==b'RIFF',path
 count=struct.unpack_from('<H',data,22)[0]
 return {'variable':variable,'variable_path':('/private/' if private else '/shared_owner/')+variable,
         'tag':tag,'palette':path,'default':default,'min':0,'max':count-1,
         'colors':[[v/255 for v in rgba] for rgba in array(data[24:24+count*4],'4B')]}


def material_extensions(imp,root,material):
 bindings={}
 for node in root.walk('TXM '):
  name=child(node.children[0],'NAME')
  tag=node.first('DATA').data[:4].decode('ascii')[::-1]
  if name and tag in ('MAIN','HUEB','NRML','CNRM'):bindings[tag]=texture(imp,cstring(name.data)[0])
 selectors=[]
 for node in root.walk('TXTR'):
  data=child(node,'DATA').data;count=struct.unpack_from('<H',data)[0];paths=strings(data[2:]);assert len(paths)==count
  for op in node.first('CUST').children:
   if op.tag!='TX1D':raise ValueError('Unsupported original texture selector '+op.tag)
   tag=op.data[:4].decode('ascii')[::-1];start,count=struct.unpack_from('<HH',op.data,4);variable,pos=cstring(op.data,8)
   private,default=struct.unpack_from('<Bh',op.data,pos)
   selectors.append({'tag':tag,'variable':variable,'variable_path':('/private/' if private else '/shared_owner/')+variable,
                     'min':0,'max':count-1,'default':default,'textures':[texture(imp,p) for p in paths[start:start+count]],'source_operation':'TX1D'})
 effects=list(dict.fromkeys(x['effect'] for x in material['alpha_source']))
 dual=any('color2' in e for e in effects)
 material.update(texture_bindings=bindings,texture_selectors=selectors,
                 color_mode='dual_alpha' if dual and material['alpha'] else 'dual' if dual else 'single',
                 normal_encoding='dxt5_ag' if 'CNRM' in bindings else 'rgb' if 'NRML' in bindings else 'none')
 # Hash the actual source programs that define the color operations used here.
 programs=['pixel_program/h_color2_specmap_cbmp_ps20.psh','pixel_program/h_alpha_color2_ps11.psh','shared_program/functions.inc']
 for p in programs:imp.read(p)
 return material


def renderer(imp,path):
 cache=getattr(imp,'texture_renderer_cache',{})
 if path in cache:return cache[path]
 root=parse_iff(imp.read(path));assert root.tag=='BTRT' and root.children[0].tag=='0001',path
 destination=array(root.first('DEST').data,'I');width,height=destination[0][0],destination[1][0]
 shader_names=[cstring(n.data)[0].replace('\\','/') for n in root.first('SHTM').children if n.tag=='NAME']
 for shader in shader_names:imp.read(shader)
 for p in ['pixel_program/texren_copy_c1a1.psh','vertex_program/texren_copy_c1a1.vsh']:imp.read(p)
 raw=root.first('TXTS').first('INFO').data;paths=strings(raw[4:]);assert len(paths)==struct.unpack_from('<I',raw)[0]
 textures=[texture(imp,p) for p in paths]
 quads=[]
 for node in root.first('VBS ').walk('VTXA'):
  vertices=array(node.first('DATA').data,'5f');assert len(vertices)==4
  x0,y0,_,u0,v0=vertices[0];x1,y1,_,u1,v1=vertices[2]
  assert abs(vertices[1][1]-y0)<1e-5 and abs(vertices[3][0]-x0)<1e-5
  quads.append({'rect':[x0,y0,x1-x0,y1-y0],'uv_rect':[u0,v0,u1-u0,v1-v0]})
 layers=[];by_shader={}
 for command in root.first('RCMS').children:
  if command.tag=='INFO':continue
  assert command.tag=='SRSC'
  shader_index,count=struct.unpack('<II',command.first('INFO').data);assert count==1
  vertex_index=struct.unpack('<I',command.first('RTFC').data)[0]
  shader=shader_names[shader_index];assert shader in ('shader/texren_copy_c1a1.sht','shader/texren_alphablend_c1a1.sht'),shader
  layer={'shader_index':shader_index,'shader':shader,'mode':'copy' if 'texren_copy' in shader else 'alpha',**quads[vertex_index]}
  layers.append(layer);by_shader[shader_index]=layer
 operations=[]
 for node in root.first('PCMS').walk():
  if not node.data or node.tag=='INFO':continue
  assert node.tag in ('SSTC','SST1','STFP'),(path,node.tag)
  if node.tag=='STFP':
   shader_index=struct.unpack_from('<H',node.data)[0];tag=node.data[2:6].decode('ascii')[::-1]
   pal,p=cstring(node.data,6);var,p=cstring(node.data,p);private=node.data[p]
   by_shader[shader_index]['palette']=palette(imp,pal,var,private,tag)
  else:
   shader_index=struct.unpack_from('<I',node.data)[0];tag=node.data[4:8].decode('ascii')[::-1];start=struct.unpack_from('<I',node.data,8)[0]
   assert tag=='MAIN',(path,tag)
   if node.tag=='SSTC':by_shader[shader_index]['texture']=textures[start]
   else:
    variable,p=cstring(node.data,12);count=struct.unpack_from('<I',node.data,p)[0]
    by_shader[shader_index]['selector']={'variable':variable,'variable_path':'/private/'+variable,'min':0,'max':count-1,'default':0,'textures':textures[start:start+count],'source_operation':'SST1'}
  operations.append(node.tag)
 assert all('texture' in layer or 'selector' in layer for layer in layers)
 result={'source':path,'width':width,'height':height,'layers':layers,'operations':operations,'supported':True}
 cache[path]=result;imp.texture_renderer_cache=cache
 return result


def supported_variables(surface):
 variables={p['variable'] for p in surface.get('palettes',[])}
 variables.update(s['variable'] for s in surface.get('texture_selectors',[]))
 for layer in surface.get('texture_renderer_definition',{}).get('layers',[]):
  for key in ('selector','palette'):
   if key in layer:variables.add(layer[key]['variable'])
 return variables
