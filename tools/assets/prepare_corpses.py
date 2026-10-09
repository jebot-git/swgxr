#!/usr/bin/env python3
"""Freeze original animal SAT/MGN skin at an authored incapacitated pose.

Reference assets only. No creature creation, rights, loot or resource simulation.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path
import numpy as np
from prepare_characters import CharacterImporter
from character_animations import ash_summary, decode_clip, load_lat, resolve
from swg_formats import cstring, parse_iff
from planet_config import PLANETS
ROOT=Path(__file__).resolve().parents[2]

def planet_templates(planet):
    """Select explicit harvestable Creature definitions, never humanoid names."""
    directory=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/mobile'/planet
    selected={}; hashes={}
    for path in sorted(directory.glob('*.lua')):
        raw=path.read_bytes(); text=re.sub(r'--[^\n]*','',raw.decode())
        if not re.search(r'\bCreature\s*:\s*new\s*\{',text): continue
        harvest={}
        for kind in ('meat','hide','bone'):
            amount=re.search(r'\b'+kind+r'Amount\s*=\s*([0-9.]+)',text)
            source=re.search(r'\b'+kind+r'Type\s*=\s*"([^"]+)"',text)
            if amount and float(amount[1])>0 and source: harvest[kind]={'amount':float(amount[1]),'type':source[1]}
        if not harvest: continue
        block=re.search(r'\btemplates\s*=\s*\{([^}]+)\}',text,re.S)
        if not block: continue
        templates=re.findall(r'"(object/mobile/[^"\s]+\.iff)"',block[1])
        if not templates: continue
        hashes[str(path.resolve())]=hashlib.sha256(raw).hexdigest()
        for template in templates:
            selected.setdefault(template,[]).append({'source_file':str(path.resolve()),'mobile':path.stem,'harvest_definition':harvest})
    return selected,hashes

def matrix(position, quaternion):
    x,y,z,w=np.asarray(quaternion,dtype=float)/np.linalg.norm(quaternion)
    result=np.eye(4)
    result[:3,:3]=[[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],
                   [2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],
                   [2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]]
    result[:3,3]=position
    return result

def freeze(model, clip):
    """Exact first authored pose; no interpolation or synthesized animation."""
    tracks={t['bone']:t for t in clip['tracks']}
    rests=[]; poses=[]
    for index,bone in enumerate(model['bones']):
        rest=matrix(bone['rest_position'],bone['rest_rotation'])
        track=tracks.get(index,{})
        pose=matrix(track.get('positions',[[0,*bone['rest_position']]])[0][1:],
                    track.get('rotations',[[0,*bone['rest_rotation']]])[0][1:])
        parent=bone['parent']
        if parent>=0:
            if parent>=index: raise ValueError('Skeleton parents must precede children')
            rest=rests[parent]@rest; pose=poses[parent]@pose
        rests.append(rest); poses.append(pose)
    transforms=np.asarray([pose@np.linalg.inv(rest) for pose,rest in zip(poses,rests)])
    for group in model.get('virtual_skin_bones',[]):
        bone=int(group['bone']); sources=group['source_bones']
        if not sources or any(i<0 or i>=bone for i in sources): raise ValueError('Invalid source dense-skin matrix group')
        # Same exact affine reduction as CharacterImporter: equal residual
        # source influences collapse into their mean skin matrix, not a joint.
        transforms[bone]=transforms[sources].mean(axis=0)
    surfaces=[]
    for part in model['parts']:
        for surface in part['mesh']['surfaces']:
            positions=np.asarray(surface['vertices']).reshape(-1,3)
            normals=np.asarray(surface['normals']).reshape(-1,3)
            count=len(positions)
            bones=np.asarray(surface['bones'],dtype=int).reshape(count,-1)
            weights=np.asarray(surface['weights']).reshape(count,-1)
            if not np.allclose(weights.sum(axis=1),1,atol=0.001): raise ValueError('Skin weight sum is invalid')
            if bones.min()<0 or bones.max()>=len(transforms): raise ValueError('Skin references absent bone')
            blended=np.sum(transforms[bones]*weights[:,:,None,None],axis=1)
            vertices=np.einsum('nij,nj->ni',blended,np.column_stack([positions,np.ones(count)]))[:,:3]
            result_normals=np.einsum('nij,nj->ni',blended[:,:3,:3],normals)
            result_normals/=np.maximum(np.linalg.norm(result_normals,axis=1)[:,None],1e-12)
            # Animation is baked once; material selectors/palettes remain live.
            result={k:v for k,v in surface.items() if k not in ('bones','weights','blend_shapes','triangle_zones')}
            result.update(vertices=vertices.reshape(-1).tolist(),normals=result_normals.reshape(-1).tolist())
            surfaces.append(result)
    all_vertices=np.concatenate([np.asarray(s['vertices']).reshape(-1,3) for s in surfaces])
    bounds={'min':all_vertices.min(axis=0).tolist(),'max':all_vertices.max(axis=0).tolist()}
    return {'schema_version':1,'material_pipeline':'original_character','coordinate_system':'Godot Y-up, SWG Z mirrored; original authored skeletal pose frozen at frame zero','surfaces':surfaces},bounds

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--template',action='append',default=[])
    parser.add_argument('--snapshot',type=Path)
    parser.add_argument('--planet',choices=PLANETS,help='Explicit harvestable animals in local Core3 planet mobile definitions')
    parser.add_argument('--tre-dir',type=Path,default=ROOT/'runtime/asset_sources/active_tre')
    parser.add_argument('--out',type=Path,default=ROOT/'runtime/assets/corpses')
    args=parser.parse_args(); templates=set(args.template)
    snapshot_bytes=args.snapshot.read_bytes() if args.snapshot else b''
    if snapshot_bytes:
        snapshot=json.loads(snapshot_bytes)
        templates.update(str(x['template']) for x in snapshot.get('corpses',[]) if x.get('template'))
    species_sources,source_hashes=planet_templates(args.planet) if args.planet else ({},{})
    templates.update(species_sources)
    if not templates: parser.error('Specify actual --template, --planet or --snapshot containing corpses')
    imp=CharacterImporter(args.tre_dir,args.out)
    path=args.out/'catalog.json'
    catalog=json.loads(path.read_text()) if path.exists() else {'schema_version':1,'items':{},'aliases':{},'provenance':{'dependencies':{}},'failures':[]}
    for template in sorted(templates):
        shared=str(Path(template).parent/('shared_'+Path(template).name)) if '/shared_' not in template else template
        server=shared.replace('/shared_','/')
        entry={'template':server,'shared_template':shared,'status':'unsupported'}
        source_definitions=species_sources.get(server,catalog['items'].get(server,{}).get('source_planet_definitions',[]))
        if source_definitions: entry['source_planet_definitions']=source_definitions
        try:
            appearance=imp.appearance(shared); model=imp.model(appearance)
            raw=parse_iff(imp.read(appearance)).first('LATX').data
            _,offset=cstring(raw,2); lat,_=cstring(raw,offset)
            ash,table=load_lat(imp,lat); graph=ash_summary(imp,ash)
            state=next((s for s in graph['states'] if s['name']=='incapacitated_face_up'),None)
            if state is None: raise ValueError('No authored incapacitated pose state')
            leaves=resolve(table[state['loop']],{})
            if len(leaves)!=1: raise ValueError('Pose selector has ambiguous leaves')
            names={b['name']:i for i,b in enumerate(model['bones'])}
            clip=decode_clip(imp,leaves[0]['source'],model['bones'],names)
            if not clip['tracks']: raise ValueError('Original pose has no matching bone tracks')
            frozen,bounds=freeze(model,clip)
            encoded=json.dumps(frozen,separators=(',',':')).encode()
            sha=hashlib.sha256(encoded).hexdigest(); relative='models/'+sha[:24]+'.json'
            imp.write(relative,frozen)
            entry.update(status='ready',appearance=appearance,model=relative,model_sha256=sha,bounds=bounds,
                         material_pipeline='original_character',bones=len(model['bones']),source_lat=lat,source_ash=ash,
                         virtual_skin_groups=len(model.get('virtual_skin_bones',[])),
                         dense_skin_policy='Exact affine average of original source skin matrices; no influence truncation',
                         source_clip=clip['source'],source_clip_sha256=clip['source_sha256'],source_logical=state['loop'],
                         source_state=state['name'],frozen_time_seconds=0,
                         pose_policy='Frozen original incapacitated pose for backend-confirmed DEAD creature; not a separately authored death clip',
                         scale_policy='Original asset meter scale times authoritative creature scale; no preview normalization')
        except Exception as exc: entry['error']=str(exc)
        catalog['items'][server]=entry; catalog['aliases'][shared]=server
        print(server,entry['status'],entry.get('error',''),flush=True)
    catalog['provenance']['dependencies'].update(imp.dependencies)
    catalog['provenance'].setdefault('core3_files_sha256',{}).update(source_hashes)
    if args.planet:
        catalog.setdefault('planets',{})[args.planet]={'templates':sorted(species_sources),'source_definitions':len(source_hashes),
          'selection_policy':'Concrete planet Creature:new definitions with explicit positive meat/hide/boneAmount and corresponding nonempty source resource type; source template arrays only. No spawn or reward authority.'}
    if snapshot_bytes:
        sha=hashlib.sha256(snapshot_bytes).hexdigest(); selection=args.out/'selections'/f'{sha}.json';selection.parent.mkdir(exist_ok=True);selection.write_bytes(snapshot_bytes)
        catalog['provenance'].setdefault('selections',{})[str(selection.resolve())]={'sha256':sha,'source_path':str(args.snapshot.resolve())}
    catalog['failures']=[{'template':k,'error':v.get('error')} for k,v in catalog['items'].items() if v['status']!='ready']
    imp.write('catalog.json',catalog)
    print(json.dumps({'ready':sum(v['status']=='ready' for v in catalog['items'].values()),'failures':catalog['failures'],'source_hashes':len(catalog['provenance']['dependencies'])}))
    return bool(catalog['failures'])
if __name__=='__main__': raise SystemExit(main())
