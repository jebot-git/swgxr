#!/usr/bin/env python3
"""Verify local corpse geometry, immutable inputs and original TRE provenance."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from swg_formats import TreSet
from prepare_corpses import ROOT, freeze

def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--catalog',type=Path,default=ROOT/'runtime/assets/corpses/catalog.json');args=ap.parse_args()
    catalog=json.loads(args.catalog.read_text());base=args.catalog.parent;tre=TreSet(ROOT/'runtime/asset_sources/active_tre');errors=[];model_count=0
    for path,source in catalog['provenance']['dependencies'].items():
        try:
            if hashlib.sha256(tre.read(path)).hexdigest()!=source['sha256']:errors.append('Changed source '+path)
        except Exception as exc:errors.append(f'{path}: {exc}')
    for path,source in catalog['provenance'].get('selections',{}).items():
        if hashlib.sha256(Path(path).read_bytes()).hexdigest()!=source['sha256']:errors.append('Changed selection '+path)
    for path,sha in catalog['provenance'].get('core3_files_sha256',{}).items():
        if hashlib.sha256(Path(path).read_bytes()).hexdigest()!=sha:errors.append('Changed original Core3 selection '+path)
    for template,entry in catalog['items'].items():
        if entry['status']!='ready':errors.append('Unsupported '+template+': '+entry.get('error',''));continue
        raw=(base/entry['model']).read_bytes()
        if hashlib.sha256(raw).hexdigest()!=entry['model_sha256']:errors.append('Changed converted model '+template)
        data=json.loads(raw);model_count+=1
        positions=[]
        for surface in data['surfaces']:
            vertices=np.asarray(surface['vertices']).reshape(-1,3);positions.append(vertices)
            if not np.isfinite(vertices).all():errors.append('Nonfinite geometry '+template)
            if min(surface['indices'])<0 or max(surface['indices'])>=len(vertices):errors.append('Invalid triangles '+template)
            if any(key in surface for key in ['bones','weights']):errors.append('Unfrozen runtime skin '+template)
            if not (base/surface['texture']).is_file():errors.append('Missing original texture '+template)
        vertices=np.concatenate(positions)
        if not np.allclose(vertices.min(axis=0),entry['bounds']['min']) or not np.allclose(vertices.max(axis=0),entry['bounds']['max']):errors.append('Incorrect posed bounds '+template)
        if entry['source_clip_sha256']!=catalog['provenance']['dependencies'][entry['source_clip']]['sha256']:errors.append('Clip provenance mismatch '+template)
    # Independent numerical check: inverse bind translation followed by source
    # pose quarter turn. Catches quaternion ordering/inverse-bind mistakes.
    model={'bones':[{'parent':-1,'rest_position':[1,0,0],'rest_rotation':[0,0,0,1]}],
           'parts':[{'mesh':{'surfaces':[{'vertices':[2,0,0],'normals':[1,0,0],'bones':[0],'weights':[1]}]}}]}
    clip={'tracks':[{'bone':0,'positions':[[0,2,0,0]],'rotations':[[0,0,0,2**-.5,2**-.5]]}]}
    result,_=freeze(model,clip);surface=result['surfaces'][0]
    if not np.allclose(surface['vertices'],[2,1,0]) or not np.allclose(surface['normals'],[0,1,0],atol=1e-9):errors.append('Source pose inverse-bind numerical regression')
    dense={'bones':[{'parent':-1,'rest_position':[0,0,0],'rest_rotation':[0,0,0,1]} for _ in range(3)],
           'virtual_skin_bones':[{'bone':2,'source_bones':[0,1]}],
           'parts':[{'mesh':{'surfaces':[{'vertices':[0,0,0],'normals':[0,1,0],'bones':[2],'weights':[1]}]}}]}
    clip={'tracks':[{'bone':i,'positions':[[0,x,0,0]],'rotations':[[0,0,0,0,1]]} for i,x in enumerate([1,3])]}
    result,_=freeze(dense,clip)
    if not np.allclose(result['surfaces'][0]['vertices'],[2,0,0]):errors.append('Dense source influence affine average regression')
    report={'ok':not errors,'models':model_count,'source_hashes':len(catalog['provenance']['dependencies']),'errors':errors,'scope':'Original frozen animal corpse assets; no server rights/rewards validation'}
    evidence=ROOT/'runtime/evidence/corpse-asset-validation.json';evidence.parent.mkdir(exist_ok=True);evidence.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2));return bool(errors)
if __name__=='__main__':raise SystemExit(main())
