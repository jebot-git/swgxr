#!/usr/bin/env python3
"""Export source-derived, unscaled creature body/head bounds for Core3 validation."""
import hashlib
import argparse
import json
import math
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT/'tools/assets'),str(ROOT)]
from swg_formats import TreSet
from prepare_stage import qrot
from tools.pets.audit_assets import audit
OUT = ROOT/'runtime/assets/pets/body_bounds.json'
VERSION = 1


def stamp(path):
    value=path.stat()
    return [value.st_mtime_ns,value.st_size]


def fresh():
    try:
        report=json.loads(OUT.read_text())
        state=report.get('freshness',{})
        return (report.get('ready',False) and state.get('version')==VERSION and bool(state.get('inputs'))
                and all(stamp(ROOT/path)==value for path,value in state['inputs'].items()))
    except (OSError,ValueError,TypeError):
        return False


def multiply(a,b):
    w,x,y,z = a
    v,i,j,k = b
    return [w*v-x*i-y*j-z*k,w*i+x*v+y*k-z*j,w*j-x*k+y*v+z*i,w*k+x*j-y*i+z*v]


def source_bounds(model,head_index):
    """Use the same bind hierarchy and lowest vertex grounding as Avatar.configure."""
    if not 0<=head_index<len(model['bones']): raise ValueError('Original anatomical anchor unavailable')
    poses=[]
    for bone in model['bones']:
        x,y,z,w=bone['rest_rotation']
        rotation=[w,x,y,z]
        position=bone['rest_position']
        parent=bone['parent']
        if parent>=0:
            parent_position,parent_rotation=poses[parent]
            position=[a+b for a,b in zip(parent_position,qrot(parent_rotation,position))]
            rotation=multiply(parent_rotation,rotation)
        poses.append((position,rotation))
    minimum=[math.inf]*3
    maximum=[-math.inf]*3
    for part in model['parts']:
        for surface in part['mesh']['surfaces']:
            vertices=surface['vertices']
            for axis in range(3):
                minimum[axis]=min(minimum[axis],min(vertices[axis::3]))
                maximum[axis]=max(maximum[axis],max(vertices[axis::3]))
    if not all(math.isfinite(v) and abs(v)<256 for v in minimum+maximum):
        raise ValueError('Nonfinite or excessive original creature extent')
    ground=-minimum[1]
    position=poses[head_index][0]
    head=[position[0],position[1]+ground,-position[2]]
    low=[minimum[0],0.0,-maximum[2]]
    high=[maximum[0],maximum[1]+ground,-minimum[2]]
    return {'head_position':head,
            'source_head_position':[position[0],position[1],-position[2]],
            'bounds_min':[min(a,b) for a,b in zip(low,head)],
            'bounds_max':[max(a,b) for a,b in zip(high,head)],
            'visual_ground_offset':ground}


def prepare():
    evidence=audit()
    tre=TreSet(ROOT/'runtime/assets/active_tre')
    templates={}
    provenance={}
    failures=[row for row in evidence['missing'] if row['phase']!='partial_appearance']
    required={row['template'] for row in evidence['creatures'] if row['planet']=='tatooine'}
    required.update(row['template'] for row in failures if row['planet']=='tatooine')
    for row in evidence['creatures']:
        template=row['template']
        if template in templates: continue
        raw=(ROOT/row['model']).read_bytes()
        model=json.loads(raw)
        try:
            bounds=source_bounds(model,row['head_bone'])
            bounds.update(head_bone=row['anchor_name'],model_sha256=hashlib.sha256(raw).hexdigest(),
                          source_catalog=row['catalog'],source_model=row['model'],source_scale=1.0)
            sources={template.replace('/mobile/','/mobile/shared_'),model['appearance']}
            # Virtual skin joints document their derivation in this field;
            # they are already covered by the hashed converted model, not TRE paths.
            sources.update(b['source_skeleton'] for b in model['bones'] if b.get('source_skeleton','').startswith('appearance/'))
            sources.update(p['mesh']['source'] for p in model['parts'] if p['mesh'].get('source'))
            bounds['source_files']=sorted(sources)
            for source in sources:
                if source in provenance: continue
                data=tre.read(source)
                provenance[source]={'sha256':hashlib.sha256(data).hexdigest(),'archive':tre.entries[source][0].name,'bytes':len(data)}
            templates[template]=bounds
        except (ValueError,KeyError) as error:
            failures.append({'template':template,'planet':row['planet'],'error':str(error)})
    report={'schema':1,'coordinate_system':'original_x_y_up_z','templates':templates,
            'provenance':provenance,'failures':failures,
            'ready':required.issubset(templates),'missing_required_templates':sorted(required-templates.keys()),
            'policy':'Original bind-space mesh bounds and skeleton anchors with the client visual grounding correction; Core3 applies live creature scale/yaw/world pose. These are presentation contact bounds, not new gameplay collision.'}
    inputs={Path(__file__),ROOT/'tools/pets/audit_assets.py',ROOT/'runtime/assets/planets/catalog.json',
            ROOT/'runtime/assets/combat_population/sources.json'}
    inputs.update(ROOT/row['model'] for row in evidence['creatures'])
    inputs.update(ROOT/row['catalog'] for row in evidence['creatures'])
    inputs.update((ROOT/'runtime/assets/planets').glob('*/entities/sources.json'))
    inputs.update((ROOT/'runtime/assets/active_tre').glob('*.tre'))
    inputs.update(ROOT/path for path in evidence['source_hashes'] if (ROOT/path).is_file())
    report['freshness']={'version':VERSION,'inputs':{str(path.relative_to(ROOT)):stamp(path) for path in sorted(inputs) if path.exists()}}
    out=OUT
    out.parent.mkdir(parents=True,exist_ok=True)
    temporary=out.with_suffix('.json.tmp')
    temporary.write_text(json.dumps(report,separators=(',',':'))+'\n')
    temporary.replace(out)
    return report


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ensure',action='store_true',help='Only rebuild when source/catalog/model file stamps or generator change')
    arguments=parser.parse_args()
    if arguments.ensure and fresh():
        print(json.dumps({'ready':True,'cached':True,'path':str(OUT)}))
        raise SystemExit(0)
    result=prepare()
    print(json.dumps({'templates':len(result['templates']),'source_files':len(result['provenance']),'failures':result['failures']}))
    # Other restored planets stay local; their explicit missing data must not
    # block an otherwise complete Tatooine-only testing installation.
    raise SystemExit(not result['ready'])
