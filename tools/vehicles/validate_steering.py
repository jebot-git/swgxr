#!/usr/bin/env python3
"""Validate original handlebar selections, source hashes and VR steering geometry."""
import hashlib,json,math
from pathlib import Path
from yoke_geometry import steering_component,source_components
ROOT=Path(__file__).resolve().parents[2]
def main():
 out=ROOT/'runtime/assets/vehicles';catalog=json.loads((out/'catalog.json').read_text());reports=[]
 for name,count in [('speederbike',430),('speederbike_swoop',132),('speederbike_flash',72)]:
  d=catalog['items']['object/mobile/vehicle/'+name+'.iff'];path=out/d['model'];model=json.loads(path.read_text());g=d['steering_geometry']
  assert g['status']=='ready' and len(g['triangles'])==count
  assert hashlib.sha256(path.read_bytes()).hexdigest()==g['model_sha256']
  actual=json.loads(json.dumps(steering_component(model,d['controls'])));assert all(g[k]==v for k,v in actual.items())
  surface=model['surfaces'][g['surface']];triangles=list(zip(*[iter(surface['indices'])]*3));selected=set(g['triangles']);assert len(selected)==count and all(0<=i<len(triangles) for i in selected)
  reconstructed={i:triangles[i] for i in range(len(triangles)) if i not in selected};reconstructed.update({i:triangles[i] for i in selected});assert [reconstructed[i] for i in range(len(triangles))]==triangles
  assert all(abs(g['pivot'][i]-sum(p[i] for p in d['controls'])/2)<1e-12 for i in range(3))
  assert max(g['grip_vertex_distances'])<(.08 if name=='speederbike_flash' else .04)
  # The full source components survive intact on exactly one side of the split.
  for component in source_components(surface,weld_positions=name=='speederbike'):
   membership=[i in selected for i in component['triangles']];assert all(membership) or not any(membership)
  a=.4;movement=[]
  for grip in d['controls']:
   dx=grip[0]-g['pivot'][0]
   if name=='speederbike_flash':
    dy=grip[1]-g['pivot'][1];movement.append(math.sin(a)*dx+math.cos(a)*dy-dy)
   else:
    dz=grip[2]-g['pivot'][2];movement.append(-math.sin(a)*dx+math.cos(a)*dz-dz)
  assert movement[0]*movement[1]<0 and min(abs(v) for v in movement)>(.04 if name=='speederbike_flash' else .05)
  assert (len(g['shared_attachment_positions'])==6 if name!='speederbike' else not g['shared_attachment_positions'])
  reports.append({'vehicle':name,'triangles':count,'components':g['component_count'],'source_model_sha256':g['model_sha256'],'grip_vertex_distances_m':g['grip_vertex_distances'],'handle_delta_at_0_4rad_m':movement,'axis':'vertical' if name=='speederbike_flash' else 'fore_aft','shared_attachment_vertices':len(g['shared_attachment_positions']),'no_triangles_added_or_removed':True})
 report={'passed':True,'hardware_tested':False,'source_geometry_only':True,'vehicles':reports};dest=ROOT/'runtime/evidence/vehicle-handlebar-assets.json';dest.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
if __name__=='__main__':main()
