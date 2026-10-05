#!/usr/bin/env python3
"""Validate source world chunk geometry, placements, POB ownership and hashes."""
import argparse,hashlib,json,math
from pathlib import Path
from swg_formats import TreSet
ROOT=Path(__file__).resolve().parents[2]

def validate(directory):
 manifest=json.loads((directory/'world.json').read_text());mesh_counts={};counts={'meshes':0,'instances':0,'cells':0,'chunks':0,'verified_dependencies':0,'vertices':0,'unique_triangles':0,'placed_objects':0}
 for key,entry in manifest['meshes'].items():
  model=json.loads((directory/entry['path']).read_text());triangles=0
  for surface in model['surfaces']:
   n=len(surface['vertices'])//3;assert n>0
   for field,width in [('vertices',3),('normals',3),('uv',2),('colors',4)]:
    values=surface.get(field,[]);assert len(values) in (0,n*width);assert all(math.isfinite(v) for v in values)
   indices=surface['indices'];assert len(indices)%3==0;assert all(0<=i<n for i in indices)
   triangles+=len(indices)//3;counts['vertices']+=n
   if surface.get('texture'):assert (directory/surface['texture']).read_bytes().startswith(b'\x89PNG')
  assert triangles==entry['triangles'];mesh_counts[key]=triangles;counts['unique_triangles']+=triangles;counts['meshes']+=1
 objects=set();instanced_triangles=0
 for key,descriptor in manifest['chunks'].items():
  chunk=json.loads((directory/descriptor['path']).read_text());assert len(chunk['instances'])==descriptor['instance_count'];assert len(chunk['cells'])==descriptor['cell_count'];counts['chunks']+=1
  for entry in chunk['instances']:
   assert entry['mesh'] in mesh_counts;assert all(math.isfinite(v) for v in entry['position']+entry['quaternion']);assert abs(sum(v*v for v in entry['quaternion'])-1)<.002
   if 'cell_id' in entry:assert entry['cell_id'] in chunk['cells'];assert entry['is_exterior']==chunk['cells'][entry['cell_id']]['is_exterior']
   objects.add(entry['object_id']);counts['instances']+=1;instanced_triangles+=mesh_counts[entry['mesh']]
  for cell in chunk['cells'].values():
   n=len(cell['floor_vertices'])//3;assert all(0<=i<n for i in cell['floor_indices']);counts['cells']+=1
   for portal in cell['portals']:assert portal['leads_to'] in chunk['cells']
 counts['placed_objects']=len(objects);counts['instanced_triangles']=instanced_triangles
 for key in ['meshes','instances','cells','chunks','placed_objects','unique_triangles','instanced_triangles']:assert counts[key]==manifest['statistics'][key],(key,counts[key],manifest['statistics'][key])
 tre=TreSet(manifest['provenance']['tre_directory'])
 for path,record in manifest['provenance']['dependencies'].items():
  data=tre.read(path);assert len(data)==record['bytes'] and hashlib.sha256(data).hexdigest()==record['sha256'],path;counts['verified_dependencies']+=1
 counts['status']='passed';counts['skipped_objects']=manifest['statistics']['skipped_objects'];counts['conversion_failures']=manifest['statistics']['conversion_failures'];(directory/'validation_report.json').write_text(json.dumps(counts,indent=2)+'\n');return counts

if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--directory',type=Path,default=ROOT/'runtime/assets/tatooine_world');print(json.dumps(validate(p.parse_args().directory),indent=2))
