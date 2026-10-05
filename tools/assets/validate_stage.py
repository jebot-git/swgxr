#!/usr/bin/env python3
"""Validate generated stage geometry and provenance against local original data."""
import hashlib,json,math
from pathlib import Path
from swg_formats import TreSet
ROOT=Path(__file__).resolve().parents[2]
def main():
    path=ROOT/'runtime/assets/mos_eisley/scene.json'
    scene=json.loads(path.read_text());tre=TreSet(scene['provenance'].get('tre_directory',str(ROOT/'runtime/assets/tre')))
    assert scene['provenance']['starport_object_id']==1106368
    meshes=scene['meshes'];starport=[i for i in scene['instances'] if i['object_id']==1106368]
    assert len(starport)==17, f'Expected all 17 starport cells, got {len(starport)}'
    assert len(meshes)>50
    assert len(scene['instances'])>100
    vertices=triangles=0
    for key,m in meshes.items():
        assert key in tre.entries
        for s in m['surfaces']:
            n=len(s['vertices'])//3;vertices+=n
            assert len(s['vertices'])==3*n and n>0
            assert all(math.isfinite(v) for v in s['vertices'])
            assert len(s['normals']) in (0,3*n)
            assert len(s['uv']) in (0,2*n)
            assert len(s['indices'])%3==0
            assert all(isinstance(i,int) and 0<=i<n for i in s['indices'])
            triangles+=len(s['indices'])//3
            if s['texture']:
                p=path.parent/s['texture'];assert p.is_file() and p.read_bytes().startswith(b'\x89PNG')
    for i in scene['instances']:
        assert i['mesh'] in meshes
        assert abs(sum(x*x for x in i['quaternion'])-1)<0.002
    cells=scene.get('cells',{})
    assert len(cells)==17, 'Original POB cell ownership must not be flattened'
    for key,cell in cells.items():
        assert key==f"{cell['building_object_id']}:{cell['cell_index']}"
        v=cell['floor_vertices'];indices=cell['floor_indices']
        assert len(v)%3==0 and len(indices)%3==0
        assert all(math.isfinite(x) for x in v)
        assert all(0<=i<len(v)//3 for i in indices)
        for portal in cell['portals']:
            assert portal['leads_to'] in cells
            assert len(portal['vertices'])>=9 and len(portal['vertices'])%3==0
        assert all(cell['bounds_min'][i]<=cell['bounds_max'][i] for i in range(3))
    for instance in starport:
        assert instance['cell_id'] in cells
        cell=cells[instance['cell_id']]
        assert instance['cell_name']==cell['name'] and instance['is_exterior']==cell['is_exterior']
    for name,dep in scene['provenance']['dependencies'].items():
        data=tre.read(name)
        assert len(data)==dep['bytes']
        assert hashlib.sha256(data).hexdigest()==dep['sha256'],name
    report={'status':'passed','starport_cells':len(starport),'cell_ownership_records':len(cells),'meshes':len(meshes),'instances':len(scene['instances']),'unique_vertices':vertices,'unique_triangles':triangles,'verified_dependencies':len(scene['provenance']['dependencies']),'spawn':scene['spawn'],'notes':'Geometry/provenance validation; actual grounding/movement/collision tested separately by Godot stage smoke.'}
    (path.parent/'validation_report.json').write_text(json.dumps(report,indent=2))
    print(json.dumps(report,indent=2))
if __name__=='__main__':main()
