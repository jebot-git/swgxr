#!/usr/bin/env python3
"""Read-only source-geometry audit of finite exterior portal closure candidates.

Does not rewrite assets or assert every distant parallel wall is an obstruction.
Reports original converted CMSH geometry, reproducing collision detail selection.
"""
import argparse
import collections
import json
import math
from pathlib import Path
import numpy as np


def transform(position, quaternion, scale=(1,1,1)):
    x,y,z,w=np.asarray(quaternion)/np.linalg.norm(quaternion)
    matrix=np.eye(4)
    matrix[:3,:3]=np.array([[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],
                          [2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],
                          [2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]])@np.diag(scale)
    matrix[:3,3]=position
    return matrix


def meshes(definition, matrix=None):
    matrix=np.eye(4) if matrix is None else matrix
    kind=definition.get('type')
    if kind=='transform':
        child=np.eye(4);child[:3,:]=np.array(definition['matrix']).reshape(3,4)
        yield from meshes(definition['child'],matrix@child)
    elif kind in ('component','composite','detail'):
        children=definition.get('children',[])
        for child in children[1 if kind=='detail' and len(children)>1 else 0:]:
            yield from meshes(child,matrix)
    elif kind=='mesh':
        vertices=np.array(definition['vertices']).reshape(-1,3)
        vertices=vertices@matrix[:3,:3].T+matrix[:3,3]
        yield vertices[np.array(definition['indices'],dtype=int).reshape(-1,3)]


def clip(poly, normal, offset):
    out=[]
    for a,b in zip(poly,poly[1:]+poly[:1]):
        da,db=np.dot(normal,a)-offset,np.dot(normal,b)-offset
        ia,ib=da>=-1e-8,db>=-1e-8
        if ia:out.append(a)
        if ia!=ib and abs(da-db)>1e-12:out.append(a+(b-a)*(da/(da-db)))
    return out


def area(poly,normal):
    if len(poly)<3:return 0.0
    return sum(abs(np.dot(np.cross(poly[i]-poly[0],poly[i+1]-poly[0]),normal))*.5 for i in range(1,len(poly)-1))


def center_inside(triangle,center,normal):
    # Orthogonal projection keeps aperture and triangle in the same plane.
    projected=triangle-np.outer((triangle-center)@normal,normal)
    crosses=[np.dot(np.cross(projected[(i+1)%3]-projected[i],center-projected[i]),normal) for i in range(3)]
    return min(crosses)>=-1e-6 or max(crosses)<=1e-6


def audit(triangles,aperture):
    center=aperture.mean(axis=0);normal=np.cross(aperture[1]-aperture[0],aperture[2]-aperture[0]);length=np.linalg.norm(normal)
    if length<1e-8:return {'invalid_portal':True}
    normal/=length;planes=[];inradius=float('inf')
    for a,b in zip(aperture,np.roll(aperture,-1,axis=0)):
        n=np.cross(b-a,normal);n/=np.linalg.norm(n)
        if n@(center-a)<0:n=-n
        planes.append((n,n@a));inradius=min(inradius,float(n@(center-a)))
    aperture_area=area(list(aperture),normal)
    bound=min(1.5,.5*inradius)
    faces=[]
    for triangle in triangles:
        fn=np.cross(triangle[1]-triangle[0],triangle[2]-triangle[0]);length=np.linalg.norm(fn)
        if length<1e-9 or abs(fn@normal)/length<.95:continue
        poly=list(triangle)
        for n,d in planes:
            poly=clip(poly,n,d)
            if len(poly)<3:break
        overlap=area(poly,normal)
        if overlap<1e-6:continue
        distances=(np.array(poly)-center)@normal
        near=0.0 if min(distances)<=0<=max(distances) else float(min(abs(distances)))
        if near>32:continue
        center_hit=center_inside(triangle,center,normal)
        fn/=length
        center_offset=float(fn@(triangle[0]-center)/(fn@normal))
        faces.append(dict(nearest_m=near,signed_center_offset_m=center_offset,
                          slab_min_m=float(min(distances)),slab_max_m=float(max(distances)),
                          overlap_fraction=overlap/aperture_area,center_hit=bool(center_hit)))
    faces.sort(key=lambda f:abs(f['signed_center_offset_m']))
    groups={}
    for face in faces:
        key=round(face['signed_center_offset_m'],3)
        if key not in groups:groups[key]=dict(offset_m=key,overlap_fraction=0,triangles=0,center_hit=False)
        group=groups[key];group['overlap_fraction']+=face['overlap_fraction'];group['triangles']+=1;group['center_hit']|=face['center_hit']
    planes_sorted=sorted(groups.values(),key=lambda g:abs(g['offset_m']))
    nearest=next((g for g in planes_sorted if g['center_hit']),None)
    return dict(normal=normal.tolist(),inradius_m=inradius,expansion_bound_m=bound,aperture_area_m2=aperture_area,
                nearest_center_plane=nearest,nearest_overlap_plane=planes_sorted[0] if planes_sorted else None,
                planes=planes_sorted[:12],within_expansion=bool(nearest and abs(nearest['offset_m'])<=bound),
                exceeds_10cm=bool(nearest and abs(nearest['offset_m'])>.1001))


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--world',type=Path,default=Path('runtime/assets/tatooine_world/world.json'))
    parser.add_argument('--stage',type=Path,default=Path('runtime/assets/mos_eisley/scene.json'))
    parser.add_argument('--output',type=Path,default=Path('runtime/evidence/core2/portal-closure-audit.json'))
    args=parser.parse_args();world=json.loads(args.world.read_text());definitions=world['collisions'];cache={};prototypes={};instances=0;skipped_props=0
    if args.stage.exists():definitions.update(json.loads(args.stage.read_text()).get('collisions',{}))
    paths=sorted((args.world.parent/'chunks').glob('*.json'))+([args.stage] if args.stage.exists() else [])
    for path in paths:
        chunk=json.loads(path.read_text())
        for entry in chunk['instances']:
            cell=chunk['cells'].get(entry.get('cell_id',''))
            if not cell or not entry.get('collision_owner',True):continue
            collision=entry.get('collision_id','')
            if collision!=cell.get('collision_id'):
                skipped_props+=1;continue
            definition=definitions.get(collision,{}).get('extent',{})
            if collision not in cache:
                arrays=list(meshes(definition));cache[collision]=np.concatenate(arrays) if arrays else np.empty((0,3,3))
            if not len(cache[collision]):continue
            inverse=np.linalg.inv(transform(entry.get('position',[0,0,0]),entry.get('quaternion',[0,0,0,1]),entry.get('scale',[1,1,1])))
            for portal in cell.get('portals',[]):
                if not portal.get('passable'):continue
                verts=np.array(portal['vertices']).reshape(-1,3);verts=verts@inverse[:3,:3].T+inverse[:3,3]
                key=(collision,portal['id'])
                if key not in prototypes:
                    prototypes[key]=dict(collision=collision,portal_id=portal['id'],exterior=bool(cell.get('is_exterior')),instances=[],local_vertices=verts.tolist(),max_instance_portal_deviation_m=0,**audit(cache[collision],verts))
                prototypes[key]['max_instance_portal_deviation_m']=max(prototypes[key]['max_instance_portal_deviation_m'],float(np.max(np.abs(verts-np.array(prototypes[key]['local_vertices'])))))
                prototypes[key]['instances'].append(dict(cell=entry['cell_id'],chunk=path.stem))
                instances+=1
    rows=list(prototypes.values());exterior=[r for r in rows if r['exterior']];interior=[r for r in rows if not r['exterior']]
    def stats(values):
        offsets=[abs(r['nearest_center_plane']['offset_m']) for r in values if r.get('nearest_center_plane')]
        return dict(portals=len(values),with_center_plane=len(offsets),within_10cm=sum(x<=.1001 for x in offsets),
                    offset_10cm_to_bound=sum(r.get('exceeds_10cm',False) and r.get('within_expansion',False) for r in values),
                    beyond_bound=sum(r.get('exceeds_10cm',False) and not r.get('within_expansion',False) for r in values),
                    nonvertical=sum(abs(r.get('normal',[0,0,0])[1])>.25 for r in values),
                    percentiles_m={str(q):float(np.percentile(offsets,q)) for q in [0,25,50,75,90,95,100]} if offsets else {})
    report=dict(read_only=True,source_world=str(args.world),instance_portals=instances,skipped_non_shell_instances=skipped_props,unique_geometry_portals=len(rows),exterior=stats(exterior),interior=stats(interior),
                note='Distant center intersections can be opposite walls behind a correctly open portal, not proven blockers. Overlap fractions sum projected authored triangles.',portals=rows)
    args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({k:v for k,v in report.items() if k!='portals'},indent=2))
if __name__=='__main__':main()
