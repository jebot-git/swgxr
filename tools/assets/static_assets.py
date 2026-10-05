"""Reusable read-only static SWG asset conversion for streamed world chunks."""
from pathlib import Path
import hashlib,io,struct,json,math,itertools,collections
from PIL import Image
from swg_formats import TreSet,parse_iff,cstring,refs
from prepare_stage import mirror,qmirror,qrot
from collision_formats import appearance as collision_appearance, floor as collision_floor, extent as collision_extent, godot_matrix, transform_floor
from shader_alpha import shader_alpha

class StaticAssets:
 def __init__(self,tre,out):
  self.t=TreSet(tre);self.out=Path(out);self.out.mkdir(parents=True,exist_ok=True)
  self.dependencies={};self.failures=[];self.meshes={};self.materials={};self.appearances={};self.templates={};self.buildings={};self.collisions={};self.effect_alpha_cache={}
 def read(self,path):
  path=path.lower().replace('\\','/');data=self.t.read(path)
  self.dependencies[path]={'archive':self.t.entries[path][0].name,'sha256':hashlib.sha256(data).hexdigest(),'bytes':len(data)}
  if not data:raise ValueError('Source archive entry is empty: '+path)
  return data
 def material(self,path):
  if path in self.materials:return self.materials[path]
  result={'shader':path,'texture':''}
  try:
   root=parse_iff(self.read(path));candidates=[]
   for node in root.walk('TXM '):
    named=next(node.walk('NAME'),None)
    if named is None:continue
    name=named.data;tag=node.first('DATA').data[:4]
    candidates.append((0 if tag==b'NIAM' else 1,cstring(name)[0].replace('\\','/')))
   if not candidates:candidates=[(0,p) for p in refs(self.read(path)) if p.endswith(('.dds','.tga'))]
   if not candidates:
    if root.tag=='OPST':
     alias=cstring(root.first('INFO').data)[0]
     raise ValueError('Unresolved object shader alias '+repr(alias)+'; OPST requires owner-provided material binding, not a textureless material')
    raise ValueError('No source diffuse texture reference in '+root.tag+' shader')
   source=min(candidates)[1]
   if 'texture/' in source:source=source[source.index('texture/'):]
   data=self.read(source);relative='textures/'+hashlib.sha256(data).hexdigest()[:20]+'.png';dest=self.out/relative;dest.parent.mkdir(exist_ok=True)
   if not dest.exists():Image.open(io.BytesIO(data)).convert('RGBA').save(dest)
   result.update(texture=relative,texture_source=source)
   result.update(shader_alpha(root,self.read,self.effect_alpha_cache))
  except Exception as error:self.failures.append({'resource':path,'phase':'material','error':str(error)})
  self.materials[path]=result;return result
 def mesh(self,path):
  if path in self.meshes:return [{'mesh':path}]
  root=parse_iff(self.read(path));assert root.tag=='MESH';surfaces=[];bounds=[]
  for surface in root.first('SPS ').children[0].children:
   if not surface.children:continue
   shader=cstring(surface.first('NAME').data)[0];vtx=surface.first('VTXA');flags,count=struct.unpack('<II',vtx.first('INFO').data);raw=vtx.first('DATA').data
   if not count:continue
   stride=len(raw)//count;vertices=[];normals=[];uv=[];colors=[]
   for i in range(count):
    pos=i*stride;assert flags&1 and not flags&2,(path,flags)
    point=mirror(struct.unpack_from('<3f',raw,pos));pos+=12;vertices.extend(point);bounds.append(point)
    if flags&4:normals.extend(mirror(struct.unpack_from('<3f',raw,pos)));pos+=12
    if flags&8:b,g,r,a=raw[pos:pos+4];pos+=4;colors.extend([r/255,g/255,b/255,a/255])
    if flags&16:pos+=4
    for j in range((flags>>8)&15):
     dimensions=((flags>>(12+j*2))&3)+1;values=struct.unpack_from('<'+'f'*dimensions,raw,pos);pos+=4*dimensions
     if j==0:uv.extend([values[0],values[1] if dimensions>1 else 0])
    assert pos==(i+1)*stride,(path,flags,stride,pos-i*stride)
   data=surface.first('INDX').data;n=struct.unpack_from('<I',data)[0]
   if not n:continue
   width=(len(data)-4)//n;assert width in (2,4)
   indices=list(struct.unpack_from('<'+('H' if width==2 else 'I')*n,data,4));assert max(indices)<count
   result={'vertices':vertices,'normals':normals,'uv':uv,'indices':indices,**self.material(shader)}
   if colors:result['colors']=colors
   surfaces.append(result)
  if not surfaces:raise ValueError('No static triangles '+path)
  result={'source':path,'surfaces':surfaces}
  import json
  relative='meshes/'+hashlib.sha256(path.encode()).hexdigest()[:20]+'.json';destination=self.out/relative;destination.parent.mkdir(exist_ok=True);destination.write_text(json.dumps(result,separators=(',',':')))
  self.meshes[path]={'path':relative,'bounds_min':[min(p[i] for p in bounds) for i in range(3)],'bounds_max':[max(p[i] for p in bounds) for i in range(3)],'surfaces':len(surfaces),'triangles':sum(len(s['indices'])//3 for s in surfaces),'vertices':sum(len(s['vertices'])//3 for s in surfaces)}
  return [{'mesh':path}]
 def transform_mesh(self,path,matrix,component):
  identity=(1,0,0,0,0,1,0,0,0,0,1,0)
  if all(abs(a-b)<1e-7 for a,b in zip(matrix,identity)):return path
  key=path+'#'+hashlib.sha256(component.encode()+struct.pack('<12f',*matrix)).hexdigest()[:12]
  if key in self.meshes:return key
  model=json.loads((self.out/self.meshes[path]['path']).read_text());points=[]
  a,b,c,tx,d,e,f,ty,g,h,i,tz=matrix;det=a*(e*i-f*h)-b*(d*i-f*g)+c*(d*h-e*g);assert abs(det)>1e-10
  normal_matrix=((e*i-f*h,f*g-d*i,d*h-e*g),(c*h-b*i,a*i-c*g,b*g-a*h),(b*f-c*e,c*d-a*f,a*e-b*d))
  for surface in model['surfaces']:
   vertices=[];normals=[]
   for pos in range(0,len(surface['vertices']),3):
    x,y,z=mirror(surface['vertices'][pos:pos+3]);v=mirror((a*x+b*y+c*z+tx,d*x+e*y+f*z+ty,g*x+h*y+i*z+tz));vertices.extend(v);points.append(v)
   for pos in range(0,len(surface['normals']),3):
    n=mirror(surface['normals'][pos:pos+3]);v=[sum(row[j]*n[j] for j in range(3))/det for row in normal_matrix];length=math.sqrt(sum(x*x for x in v));normals.extend(mirror([x/length for x in v]))
   surface['vertices']=vertices;surface['normals']=normals
   if det<0:
    indices=surface['indices']
    for pos in range(0,len(indices),3):indices[pos+1],indices[pos+2]=indices[pos+2],indices[pos+1]
  model.update(source_mesh=path,source_component=component,component_transform=list(matrix))
  relative='meshes/'+hashlib.sha256(key.encode()).hexdigest()[:20]+'.json';(self.out/relative).write_text(json.dumps(model,separators=(',',':')))
  self.meshes[key]={**self.meshes[path],'path':relative,'bounds_min':[min(v[j] for v in points) for j in range(3)],'bounds_max':[max(v[j] for v in points) for j in range(3)]}
  return key
 def properties(self,path,trail=()):
  if path in self.templates:return self.templates[path]
  if path in trail:raise ValueError('Cyclic template '+path)
  root=parse_iff(self.read(path));result={};derived=next(root.walk('DERV'),None)
  if derived:result.update(self.properties(cstring(derived.first('XXXX').data)[0],trail+(path,)))
  for node in root.walk('XXXX'):
   if b'\0' not in node.data:continue
   key,pos=cstring(node.data)
   if key in ('appearanceFilename','portalLayoutFilename','terrainModificationFileName','interiorLayoutFileName','clientDataFile') and node.data[pos:pos+1]==b'\1':
    value=cstring(node.data,pos+1)[0]
    if value:result[key]=value
  self.templates[path]=result;return result
 def resolve(self,path,trail=()):
  path=path.lower().replace('\\','/')
  if path in self.appearances:return self.appearances[path]
  if path in trail:raise ValueError('Cyclic appearance '+path)
  if path not in self.t.entries and not path.startswith(('appearance/','object/')):path='appearance/'+path
  root=None
  if path.endswith('.msh'):result=self.mesh(path);root=parse_iff(self.read(path))
  elif path.endswith('.iff'):
   properties=self.properties(path);appearance=properties.get('portalLayoutFilename',properties.get('appearanceFilename'))
   result=self.resolve(appearance,trail+(path,)) if appearance else []
  else:
   root=parse_iff(self.read(path));trail=trail+(path,)
   if path.endswith('.apt'):result=self.resolve(cstring(root.first('NAME').data)[0],trail)
   elif path.endswith('.lod'):
    version=root.children[0];ranges={struct.unpack_from('<I',n.data,i)[0]:struct.unpack_from('<f',n.data,i+4)[0] for n in version.children if n.tag=='INFO' for i in range(0,len(n.data),12)}
    choices=[(ranges.get(struct.unpack_from('<I',n.data)[0],1e10),cstring(n.data,4)[0]) for n in root.walk('CHLD')]
    result=self.resolve(min(choices)[1],trail)
   elif path.endswith('.pob'):result=self.building(path,root,trail)
   elif path.endswith('.cmp'):
    result=[]
    for node in root.walk('PART'):
     source,offset=cstring(node.data);matrix=struct.unpack_from('<12f',node.data,offset)
     try:component_parts=self.resolve(source,trail)
     except Exception as error:
      self.failures.append({'resource':source,'source_component':path,'phase':'component_child','error':str(error)});continue
     for part in component_parts:
      transformed={**part,'mesh':self.transform_mesh(part['mesh'],matrix,path)}
      if 'collision_id' in part:
       old=part['collision_id'];key=old+'#'+hashlib.sha256(path.encode()+struct.pack('<12f',*matrix)).hexdigest()[:12]
       if key not in self.collisions:
        definition=dict(self.collisions[old]);m=godot_matrix(matrix)
        if 'extent' in definition:definition['extent']={'type':'transform','matrix':m,'child':definition['extent']}
        if 'floor' in definition:
         definition['floor']=dict(definition['floor']);v=definition['floor']['vertices'];definition['floor']['vertices']=[value for j in range(0,len(v),3) for value in [sum(m[row*4+k]*v[j+k] for k in range(3))+m[row*4+3] for row in range(3)]]
         # Source component transforms are rigid; normalize transformed normals.
         ts=[]
         for tri in definition['floor']['triangles']:
          n=[sum(m[row*4+k]*tri['normal'][k] for k in range(3)) for row in range(3)];length=math.sqrt(sum(x*x for x in n));ts.append({**tri,'normal':[x/length for x in n] if length else n})
         definition['floor']['triangles']=ts
        definition.update(source_component=path,source_component_transform=list(matrix));self.collisions[key]=definition
       transformed['collision_id']=key
      result.append(transformed)
   else:raise ValueError('Unsupported appearance '+path+' ('+root.tag+')')
  if root is not None and path.endswith(('.msh','.lod','.cmp')):
   definition=collision_appearance(root,path,self.read);self.collisions[path]=definition
   if definition['status']=='unsupported' or 'floor_error' in definition:
    self.failures.append({'resource':path,'phase':'authored_collision','error':definition.get('reason',definition.get('floor_error'))})
   # A LOD is the collision-owning appearance. Components without their own
   # extent retain each transformed child's authored collision declaration.
   if not path.endswith('.cmp') or definition['status']=='authored' or 'floor' in definition:
    result=[{**part,'collision_id':path,'collision_owner':index==0 or definition['status']!='authored'} for index,part in enumerate(result)]
  self.appearances[path]=result;return result
 def building(self,path,root,trail):
  result=[];cells=[];portal_polygons=[]
  for node in root.first('PRTS').children:
   if node.tag=='PRTL':points=list(struct.iter_unpack('<3f',node.data[4:]));assert len(points)==struct.unpack_from('<I',node.data)[0]
   elif node.tag=='IDTL':points=list(struct.iter_unpack('<3f',node.first('VERT').data))
   else:raise ValueError('Unsupported portal polygon '+node.tag)
   portal_polygons.append(points)
  for index,node in enumerate(root.walk('CELL')):
   data=node.first('DATA').data;name,pos=cstring(data,5);appearance,pos=cstring(data,pos);floor_source=cstring(data,pos+1)[0] if pos<len(data) and data[pos] else None
   cell={'cell_index':index,'name':name,'is_exterior':index==0,'source_pob':path,'appearance':appearance,'floor_source':floor_source,'floor_points':[],'floor_indices':[],'floor_triangles':[],'portals':[],'meshes':[]}
   # CELL0005 owns a collision extent independently of its visual appearance.
   # Most room MESH appearances explicitly have NULL collision APPR records.
   # Reading only APPR would discard the actual authored room walls.
   cell_collision=None
   if node.children[0].tag=='0005':
    collision=node.children[0].children[1];cell_collision=path+'#cell:'+str(index)
    definition={'source_appearance':appearance,'source_pob':path,'source_cell_index':index,'source_extent_type':collision.tag,'coordinate_system':'Godot instance-local; SWG Z mirrored','fallback':'visual_mesh'}
    try:
     definition['extent']=collision_extent(collision);definition['status']='null' if collision.tag=='NULL' else 'authored'
     definition['fallback']='none'
    except Exception as error:
     definition.update(status='unsupported',reason=str(error));self.failures.append({'resource':cell_collision,'phase':'pob_collision','error':str(error)})
    self.collisions[cell_collision]=definition;cell['collision_id']=cell_collision
   try:
    for part_index,part in enumerate(self.resolve(appearance,trail)):
     if cell_collision:part={**part,'collision_id':cell_collision,'collision_owner':part_index==0 or self.collisions[cell_collision]['status']!='authored'}
     cell['meshes'].append(part['mesh']);result.append({**part,'pob':path,'cell_index':index,'cell_name':name,'is_exterior':index==0})
   except Exception as error:self.failures.append({'resource':appearance,'phase':'cell_geometry','error':str(error)})
   if floor_source:
    try:
     floor=collision_floor(self.read(floor_source));cell['floor_version']=floor['version'];cell['floor_normals_corrected']=floor['normals_corrected']
     cell['floor_points']=[mirror(floor['vertices'][j:j+3]) for j in range(0,len(floor['vertices']),3)]
     cell['floor_indices']=floor['indices'];cell['floor_triangles']=[{**t,'normal':mirror(t['normal'])} for t in floor['triangles']]
    except Exception as error:self.failures.append({'resource':floor_source,'phase':'cell_floor','error':str(error)})
   for floor_portal_index,portal in enumerate(node.walk('PRTL')):
    version=portal.children[0].tag;data=portal.children[0].data
    if version not in ('0004','0005'):
     self.failures.append({'resource':path,'phase':'cell_portal','error':'Unsupported portal version '+version});continue
    shift=1 if version=='0005' else 0;disabled=bool(data[0]) if shift else False;portal_id=struct.unpack_from('<I',data,shift+1)[0];adjacent=struct.unpack_from('<I',data,shift+6)[0]
    cell['portals'].append({'id':portal_id,'floor_portal_index':floor_portal_index,'adjacent':adjacent,'passable':bool(data[shift]) and not disabled,'source_disabled':disabled,'source_version':version,'points':portal_polygons[portal_id]})
   cells.append(cell)
  self.buildings[path]=cells;return result

 def place(self,node,origin):
  """Single placement path shared by retained stage and streamed world."""
  parts=self.resolve(node['template']);instances=[];cells={}
  position=mirror([node['p'][i]-origin[i] for i in range(3)])
  def point(source):return mirror([v+node['p'][i]-origin[i] for i,v in enumerate(qrot(node['q'],source))])
  def godot_point(local):return point(mirror(local))
  def direction(source):return mirror(qrot(node['q'],source))
  def bounds(mesh):
   info=self.meshes[mesh];corners=[point(mirror(v)) for v in itertools.product(*zip(info['bounds_min'],info['bounds_max']))]
   return [min(v[i] for v in corners) for i in range(3)],[max(v[i] for v in corners) for i in range(3)]
  for part in parts:
   item={'mesh':part['mesh'],'position':position,'quaternion':qmirror(node['q']),'source_template':node['template'],'object_id':node['id']}
   item.update({k:part[k] for k in ('collision_id','collision_owner') if k in part})
   item.update({k:node[k] for k in ('source_layout','source_layout_index','source_layout_transform') if k in node})
   if node.get('parent'):
    item['source_parent_id']=node['parent']
    if 'cell_id' in node:item.update({key:node[key] for key in ('cell_id','building_object_id','source_cell_object_id')});item['is_exterior']=False
   if 'cell_index' in part:item.update(cell_id=f"{node['id']}:{part['cell_index']}",cell_name=part['cell_name'],building_object_id=node['id'],is_exterior=part['is_exterior'])
   instances.append(item)
   definition=self.collisions.get(part.get('collision_id'),{})
   if 'floor' in definition and 'cell_index' not in part and not node.get('cell_id') and part.get('collision_owner',True):
    floor=definition['floor'];key=f"{node['id']}:floor:"+hashlib.sha256(part['collision_id'].encode()).hexdigest()[:8]
    converted=transform_floor(floor,godot_point,lambda n:direction(mirror(n)));lo,hi=bounds(part['mesh'])
    cells[key]={**converted,'name':'exterior_appearance_floor','is_exterior':True,'building_object_id':0,'source_object_id':node['id'],'appearance':definition['source_appearance'],'source_collision_id':part['collision_id'],'bounds_min':lo,'bounds_max':hi,'portals':[]}
  for pob in set(p['pob'] for p in parts if 'pob' in p):
   for cell in self.buildings[pob]:
    key=f"{node['id']}:{cell['cell_index']}";limits=[bounds(m) for m in cell['meshes']]
    cells[key]={k:v for k,v in cell.items() if k not in ('floor_points','meshes','portals','floor_triangles')}
    cells[key].update(building_object_id=node['id'],floor_vertices=[v for p in cell['floor_points'] for v in point(p)],
      floor_triangles=[{**t,'normal':direction(t['normal'])} for t in cell['floor_triangles']],
      portals=[{**{key:p[key] for key in ('id','floor_portal_index','passable','source_disabled','source_version')},'leads_to':f"{node['id']}:{p['adjacent']}",'vertices':[v for pnt in p['points'] for v in point(pnt)]} for p in cell['portals']],
      bounds_min=[min(b[0][i] for b in limits) for i in range(3)] if limits else position,bounds_max=[max(b[1][i] for b in limits) for i in range(3)] if limits else position)
  return instances,cells,[bounds(p['mesh']) for p in parts]

 def collision_report(self,instances):
  grouped={};counts=collections.Counter()
  for instance in instances:
   key=instance['collision_id'];definition=self.collisions[key]
   record=grouped.setdefault(key,{'source_appearance':definition['source_appearance'],'status':definition['status'],'fallback':definition['fallback'],'instances':0,'object_ids':set(),'mesh_ids':set()})
   record['instances']+=1;record['object_ids'].add(instance['object_id']);record['mesh_ids'].add(instance['mesh'])
   counts[definition['status']+'_instances']+=1
   if 'floor' in definition:counts['instances_with_appearance_floor']+=1
  for record in grouped.values():record['object_ids']=sorted(record['object_ids']);record['mesh_ids']=sorted(record['mesh_ids'])
  return {'schema_version':1,'coordinate_system':'Extent geometry is instance-local Godot; POB/standalone floor regions are stage-world Godot.',
          'floor_edge_flags':{'0':'uncrossable','1':'crossable','2':'wall_base','3':'wall_top'},
          'floor_portal_ids':'Raw cell-local index into ordered cell.portals; -1 means no portal.',
          'policy':'Authored APPR and POB extents preferred. Explicit NULL declarations have no blocking collider. Visual-mesh fallback is reserved for missing/unsupported declarations and remains reported.',
          'counts':dict(counts),'source_records':grouped}
