#!/usr/bin/env python3
"""Read-only original-media coverage check; native execution is a separate API test."""
import hashlib,json,math,struct,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'tools/assets'))
from swg_formats import TreSet,parse_iff

def run():
 source='appearance/lod/poi_all_lair_dead_log_small.lod';raw=TreSet(ROOT/'runtime/asset_sources/active_tre').read(source)
 sphere=next(n for n in parse_iff(raw).walk('SPHR') if len(n.data)==16);*center,radius=struct.unpack('<4f',sphere.data)
 model=json.loads((ROOT/'runtime/assets/inventory/models/9854e5d9496418a860d6719e.json').read_text())
 points=[]
 for surface in model['surfaces']:
  v=surface['vertices'];points.extend((v[i],v[i+1],-v[i+2]) for i in range(0,len(v),3)) # Godot Z reflection undone.
 assert all(math.dist(p,center)<=radius+.001 for p in points),'Authored enclosing sphere must cover source vertices'
 old_rejected=sum(math.dist(p,(0,0,0))>3 for p in points);assert old_rejected>0
 checks=0
 for yaw in (0,.71,math.pi/2,-2.1):
  c,s=math.cos(yaw),math.sin(yaw)
  for scale in (.5,1,2):
   world_center=(3810+scale*(c*center[0]+s*center[2]),5+scale*center[1],-4780+scale*(-s*center[0]+c*center[2]))
   for p in points:
    world=(3810+scale*(c*p[0]+s*p[2]),5+scale*p[1],-4780+scale*(-s*p[0]+c*p[2]))
    assert math.dist(world,world_center)<=radius*scale+2;checks+=1
   outside=(world_center[0]+radius*scale+2.1,world_center[1],world_center[2]);assert math.dist(outside,world_center)>radius*scale+2;checks+=1
 edge=min((p for p in points if p[1]>.15),key=lambda p:p[0])
 result={'passed':True,'native_execution':False,'source':source,'source_sha256':hashlib.sha256(raw).hexdigest(),'center_y_up':center,'radius':radius,'vertices':len(points),'old_3m_rejected_vertices':old_rejected,'transformed_coverage_checks':checks,'rotations':4,'scales':3,'above_ground_edge_source_local':edge}
 out=ROOT/'runtime/evidence/live-impact-source-bounds.json';out.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
if __name__=='__main__':run()
