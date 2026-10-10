#!/usr/bin/env python3
"""Prepare original creature saddle anchors and rider poses; no spawning or training."""
import hashlib,json,struct,sys
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[2]
sys.path[:0]=[str(ROOT/'tools/assets'),str(ROOT)]
from prepare_characters import CharacterImporter
from character_formats import datatable
from character_animations import load_lat,resolve,decode_clip
from prepare_corpses import matrix
from swg_formats import parse_iff,cstring

def saddle_anchor(read,model):
    poses={}
    for bone in model['bones']:
        pose=matrix(bone['rest_position'],bone['rest_rotation'])
        if bone['parent']>=0:pose=poses[model['bones'][bone['parent']]['name']]@pose
        poses[bone['name']]=pose
    for part in model['parts']:
        source=part['mesh'].get('source','')
        # The importer records the original MGN path on each part.
        if not source.endswith('.mgn'):continue
        for form in parse_iff(read(source)).walk('HPTS'):
            for node in form.children:
                if node.tag!='STAT':continue
                count=struct.unpack_from('<H',node.data)[0];offset=2
                for _ in range(count):
                    name,offset=cstring(node.data,offset);parent,offset=cstring(node.data,offset)
                    w,x,y,z,px,py,pz=struct.unpack_from('<7f',node.data,offset);offset+=28
                    if name=='saddle':return poses[parent]@matrix([px,py,pz],[x,y,z,w])
    raise ValueError('Original saddle hardpoint missing')

def main():
    out=ROOT/'runtime/assets/mounts';out.mkdir(parents=True,exist_ok=True)
    imp=CharacterImporter(ROOT/'runtime/asset_sources/active_tre',out)
    logical={r['sat_or_skt_name']:r['logical_saddle_name'] for r in datatable(imp.read('datatables/mount/logical_saddle_name_map.iff'))}
    saddles={r['logical_saddle_name']:r for r in datatable(imp.read('datatables/mount/saddle_appearance_map.iff'))}
    posemap={r['saddle_appearance_name']:r['rider_pose'] for r in datatable(imp.read('datatables/mount/rider_pose_map.iff'))}
    eligible={r['appearance_name'].replace('_hue','') for r in datatable(imp.read('datatables/mount/valid_scale_range.iff'))}
    bounds=json.loads((ROOT/'runtime/assets/pets/body_bounds.json').read_text())['templates']
    catalog={'schema_version':1,'items':{},'aliases':{},'rider_poses':{},'failures':[],'coordinate_system':'Godot XYZ Y-up -Z forward'}
    for template,b in bounds.items():
        model=json.loads((ROOT/b['source_model']).read_text());appearance=model['appearance'];key=logical.get(appearance)
        if key not in saddles or 'pv_' in appearance or appearance.replace('_hue','') not in eligible:continue
        try:
            saddle=saddles[key]['saddle_appearance_name'];anchor=saddle_anchor(imp.read,model)
            lod=cstring(parse_iff(imp.read(saddle)).first('NAME').data)[0]
            points={cstring(h.data,48)[0]:np.array(struct.unpack_from('<12f',h.data)).reshape(3,4) for h in parse_iff(imp.read(lod)).walk('HPNT')}
            point=(anchor@np.append(points['player'][:,3],1))[:3];point[1]+=b['visual_ground_offset'];point[2]*=-1
            catalog['items'][template]={'status':'ready','kind':'creature_mount','template':template,'appearance':appearance,'avatar_catalog':b['source_catalog'],'bounds_min':b['bounds_min'],'bounds_max':b['bounds_max'],'seats':[{'id':'driver','position':point.tolist(),'source':'Original MGN saddle hardpoint and saddle player hardpoint in bind pose','rider_pose':posemap[saddle]}],'source_model_sha256':b['model_sha256'],'saddle':saddle,'rein_anchor':b['head_position']}
            catalog['aliases'][template.replace('/mobile/','/mobile/shared_')]=template
        except Exception as e:catalog['failures'].append({'template':template,'error':str(e)})
    chars=json.loads((ROOT/'runtime/assets/characters/catalog.json').read_text());needed={d['seats'][0]['rider_pose'] for d in catalog['items'].values()}
    human=None
    for race,row in chars['races'].items():
        model=json.loads((ROOT/'runtime/assets/characters'/row['body']).read_text());bones=model['bones'];names={b['name']:i for i,b in enumerate(bones)}
        _,entries=load_lat(imp,model['animation_graph']['lat_bindings'][0]['lat']);catalog['rider_poses'][race]={}
        for pose in sorted(needed):
            leaf=resolve(entries['loop_riding'],{'rider_pose':pose,'gender':'f' if race.endswith('_female') else 'm'})[0];clip=decode_clip(imp,leaf['source'],bones,names)
            catalog['rider_poses'][race][pose]={'source':leaf['source'],'source_sha256':hashlib.sha256(imp.read(leaf['source'])).hexdigest(),'tracks':[{'name':t['name'],'position':t['positions'][0][1:],'rotation':t['rotations'][0][1:]} for t in clip['tracks']]}
        if race=='human_male':human=model
    for d in catalog['items'].values():
        tracks={t['name']:t for t in catalog['rider_poses']['human_male'][d['seats'][0]['rider_pose']]['tracks']};poses=[]
        for b in human['bones']:
            t=tracks.get(b['name'],{});m=matrix(t.get('position',b['rest_position']),t.get('rotation',b['rest_rotation']))
            if b['parent']>=0:m=poses[b['parent']]@m
            poses.append(m)
        offset=np.array(d['seats'][0]['position'])-np.array(tracks['root']['position'])
        hands=[poses[next(i for i,b in enumerate(human['bones']) if b['name']==n)] for n in ('hold_l','hold_r')]
        d['controls']=[(m[:3,3]+offset).tolist() for m in hands];d['control_bases']=[m[:3,:3].T.tolist() for m in hands]
        d['control_source']='Original rider hold sockets translated to source saddle seat; grip latches, joystick controls movement'
    catalog['dependencies']=imp.dependencies
    imp.write('catalog.json',catalog)
    print(json.dumps({'prepared':len(catalog['items']),'failures':catalog['failures']}))
    if not catalog['items'] or catalog['failures']:raise SystemExit(1)
if __name__=='__main__':main()
