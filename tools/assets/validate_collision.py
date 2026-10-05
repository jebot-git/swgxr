#!/usr/bin/env python3
"""Validate authored collider/floor graphs and retained-streamed ownership."""
import argparse,collections,json,math
from pathlib import Path

def extent(node,counts):
 typ=node['type'];counts['extent_'+typ]+=1
 if typ in ('component','composite','detail'):
  for child in node['children']:extent(child,counts)
 elif typ=='transform':
  assert len(node['matrix'])==12 and all(math.isfinite(v) for v in node['matrix']);extent(node['child'],counts)
 elif typ=='box':assert all(math.isfinite(v) for v in node['min']+node['max']) and all(a<=b for a,b in zip(node['min'],node['max']))
 elif typ=='sphere':assert len(node['center'])==3 and node['radius']>=0
 elif typ=='cylinder':assert len(node['base'])==3 and node['radius']>=0 and node['height']>=0
 elif typ=='mesh':
  n=len(node['vertices'])//3;assert len(node['vertices'])%3==0 and all(math.isfinite(v) for v in node['vertices'])
  assert len(node['indices'])%3==0 and all(0<=i<n for i in node['indices']);counts['authored_mesh_triangles']+=len(node['indices'])//3
 else:assert typ=='null',typ

def floor(vertices,indices,triangles,counts,portals=None):
 assert len(vertices)%3==0 and all(math.isfinite(v) for v in vertices)
 ids={tri['id'] for tri in triangles};assert len(ids)==len(triangles)
 solid=[]
 for tri in triangles:
  assert len(tri['indices'])==3 and all(0<=i<len(vertices)//3 for i in tri['indices'])
  assert len(tri['normal'])==3 and all(math.isfinite(v) for v in tri['normal'])
  assert len(tri['source_normal_raw'])==3 and all(math.isfinite(v) for v in tri['source_normal_raw'])
  assert len(tri['neighbors'])==3 and all(i==-1 or i in ids for i in tri['neighbors'])
  assert len(tri['edge_flags'])==3 and all(i in (0,1,2,3) for i in tri['edge_flags'])
  assert len(tri['portal_ids'])==3
  if portals is not None:assert all(i==-1 or 0<=i<len(portals) for i in tri['portal_ids'])
  if not tri['fallthrough']:solid.extend(tri['indices'])
  counts['fallthrough_triangles']+=int(tri['fallthrough']);counts['floor_triangles']+=1
 assert solid==indices

def run(stage_path,world_path,baseline=None):
 stage=json.loads(stage_path.read_text());world=json.loads(world_path.read_text());counts=collections.Counter();parts={};world_cells={}
 for manifest in (stage,world):
  assert manifest['collision_schema_version']==1
  for key,definition in manifest['collisions'].items():
   assert definition['status'] in ('authored','null','missing','unsupported')
   if 'extent' in definition:extent(definition['extent'],counts)
   if 'floor' in definition:
    f=definition['floor'];assert f['normals_corrected'];floor(f['vertices'],f['indices'],f['triangles'],counts)
 for descriptor in world['chunks'].values():
  chunk=json.loads((world_path.parent/descriptor['path']).read_text());world_cells.update(chunk['cells'])
  for instance in chunk['instances']:parts[(instance['object_id'],instance['mesh'])]=instance
 for cells in (stage['cells'],world_cells):
  for key,cell in cells.items():
   if cell['floor_triangles']:assert cell['floor_normals_corrected']
   floor(cell['floor_vertices'],cell['floor_indices'],cell['floor_triangles'],counts,cell['portals'] if 'source_pob' in cell else None)
   if 'source_pob' in cell:
    assert cell['collision_id']==cell['source_pob']+'#cell:'+str(cell['cell_index'])
    definition=world['collisions'][cell['collision_id']]
    assert definition['source_pob']==cell['source_pob'] and definition['source_cell_index']==cell['cell_index']
    counts['authored_pob_cell_placements' if definition['status']=='authored' else 'null_pob_cell_placements']+=1
   for index,portal in enumerate(cell['portals']):assert portal['floor_portal_index']==index and portal['leads_to'] in cells
   counts['exterior_floor_regions' if cell['is_exterior'] else 'interior_floor_regions']+=1
 for instance in stage['instances']:
  match=parts[(instance['object_id'],instance['mesh'])]
  for key in ('position','quaternion','cell_id','building_object_id','is_exterior','collision_id','collision_owner'):assert instance.get(key)==match.get(key),(instance['object_id'],key)
  counts['retained_world_matches']+=1
 for instance in parts.values():
  assert instance['collision_id'] in world['collisions']
  if instance.get('cell_id'):assert instance['cell_id'] in world_cells
  definition=world['collisions'][instance['collision_id']];counts['authored_instances' if definition['status']=='authored' else ('source_null_instances' if definition['status']=='null' else 'explicit_fallback_instances')]+=1
  if definition['status']=='null':assert definition['fallback']=='none'
 for oid,expected in [(1106368,17),(1280129,13),(9655494,4)]:
  owned=[i for i in stage['instances'] if i.get('building_object_id')==oid]
  assert len(owned)==expected and sum(i['is_exterior'] for i in owned)==1
 assert all(t['normal'][1]>.99 and t['source_normal_raw'][1]<-.99 for t in stage['cells']['1106368:4']['floor_triangles'])
 if baseline:
  old=json.loads((baseline/'world.json').read_text());assert set(old['meshes'])==set(world['meshes'])
  for key,entry in world['meshes'].items():
   before=json.loads((baseline/old['meshes'][key]['path']).read_text());after=json.loads((world_path.parent/entry['path']).read_text())
   assert len(before['surfaces'])==len(after['surfaces'])
   for a,b in zip(before['surfaces'],after['surfaces']):
    for field in ('vertices','normals','indices','uv','colors'):assert a.get(field)==b.get(field),(key,field)
   counts['unchanged_visual_meshes']+=1
  previous={}
  for entry in old['chunks'].values():
   for i in json.loads((baseline/entry['path']).read_text())['instances']:previous[(i['object_id'],i['mesh'])]=i
  assert set(previous)==set(parts)
  for key,instance in parts.items():
   assert instance['position']==previous[key]['position'] and instance['quaternion']==previous[key]['quaternion']
   counts['unchanged_world_transforms']+=1
 return {'status':'passed','counts':dict(counts),'stage':str(stage_path),'world':str(world_path),'baseline':str(baseline) if baseline else None}

if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--stage',type=Path,default=Path('runtime/assets/mos_eisley/scene.json'));p.add_argument('--world',type=Path,default=Path('runtime/assets/tatooine_world/world.json'));p.add_argument('--baseline',type=Path);p.add_argument('--report',type=Path);a=p.parse_args();result=run(a.stage,a.world,a.baseline)
 if a.report:a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(result,indent=2)+'\n')
 print(json.dumps(result,indent=2))
