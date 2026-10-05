#!/usr/bin/env python3
"""Extract terminal screen planes from locally converted original SWG meshes."""
import argparse, hashlib, json, math
from pathlib import Path

def sub(a,b): return [a[i]-b[i] for i in range(3)]
def dot(a,b): return sum(x*y for x,y in zip(a,b))
def cross(a,b): return [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]
def unit(v):
    length=math.sqrt(dot(v,v));return [x/length for x in v] if length else [0,0,0]
def planes(data):
    groups={}
    for surface in data.get('surfaces',[]):
        shader=surface.get('shader','')
        if not any(word in shader for word in ('anim_','screen','display','monitor','_scr')):continue
        v=surface.get('vertices',[]); normals=surface.get('normals',[])
        for start in range(0,len(surface.get('indices',[])),3):
            ids=surface['indices'][start:start+3]
            if len(ids)!=3:continue
            points=[v[i*3:i*3+3] for i in ids]
            n=unit([sum(normals[i*3+j] for i in ids) for j in range(3)])
            if abs(n[1])>.85:continue
            center=[sum(p[j] for p in points)/3 for j in range(3)]
            area=math.sqrt(dot(cross(sub(points[1],points[0]),sub(points[2],points[0])),cross(sub(points[1],points[0]),sub(points[2],points[0]))))/2
            if area<1e-6:continue
            key=(shader,*[round(x,3) for x in n],round(dot(center,n),3))
            item=groups.setdefault(key,{'shader':shader,'normal':n,'area':0,'center':[0,0,0]})
            item['area']+=area
            for j in range(3):item['center'][j]+=center[j]*area
    result=[]
    for item in groups.values():
        if item['area']<.01:continue
        item['center']=[x/item['area'] for x in item['center']]
        if item['center'][1]<.65:continue
        result.append(item)
    return sorted(result,key=lambda r:r['area'],reverse=True)[:8]
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[2]);args=parser.parse_args()
    assets=args.root/'runtime/assets';world_path=assets/'tatooine_world/world.json';services_path=assets/'services/catalog.json'
    world=json.loads(world_path.read_text());catalog=json.loads(services_path.read_text())
    wanted={r['template'] for r in catalog['static_terminals']};mapping={}
    for chunk in world['chunks'].values():
        for row in json.loads((world_path.parent/chunk['path']).read_text()).get('instances',[]):
            template=row.get('source_template','').replace('/shared_','/')
            if template in wanted:mapping.setdefault(template,set()).add(row['mesh'])
    descriptors={};failures=[]
    for template,meshes in sorted(mapping.items()):
        choices=[]
        for mesh in sorted(meshes):
            source=world_path.parent/world['meshes'][mesh]['path'];data=json.loads(source.read_text())
            for row in planes(data):choices.append(dict(row,mesh=mesh,source_path=str(source.relative_to(args.root)),sha256=hashlib.sha256(source.read_bytes()).hexdigest()))
        if choices:descriptors[template]=choices
        else:failures.append({'template':template,'reason':'No separate named screen surface in converted original mesh'})
    inventory_path=assets/'inventory/catalog.json'
    inventory=json.loads(inventory_path.read_text())
    for template,descriptor in inventory.get('items',{}).items():
        if '/terminal/' not in template or descriptor.get('status')!='ready':continue
        source=inventory_path.parent/descriptor['model'];choices=[]
        for row in planes(json.loads(source.read_text())):choices.append(dict(row,mesh=descriptor.get('appearance',''),source_path=str(source.relative_to(args.root)),sha256=hashlib.sha256(source.read_bytes()).hexdigest()))
        if choices:descriptors[template]=choices
    result={'schema_version':1,'coordinate_system':'Godot mesh-local, SWG Z mirrored','templates':descriptors,'failures':failures,'source_sha256':{str(p.relative_to(args.root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [world_path,services_path,inventory_path]},'policy':'Original screen shader triangle area centroid and normals; no replacement art or guessed authored screen positions'}
    output=assets/'services/screens.json';temporary=output.with_suffix('.tmp');temporary.write_text(json.dumps(result,indent=2)+'\n');temporary.replace(output)
    print(json.dumps({'templates':len(descriptors),'unavailable':len(failures),'output':str(output)}))
if __name__=='__main__':main()
