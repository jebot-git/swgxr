#!/usr/bin/env python3
"""Check local combat provenance, exact template values and converted texture pixels."""
import hashlib
import io
import json
from pathlib import Path
import sys
import struct
import wave

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/assets'))
from PIL import Image
from swg_formats import TreSet
from export_catalog import parse_template
from attachment_poses import bake
from swg_formats import cstring, parse_iff


def main():
    directory = ROOT / 'runtime/assets/combat'
    assets = json.loads((directory/'assets.json').read_text())
    catalog = json.loads((ROOT/'runtime/combat/catalog.json').read_text())
    tre = TreSet(ROOT/'runtime/assets/active_tre')
    checks = 0
    errors = []
    def check(value, message):
        nonlocal checks
        checks += 1
        if not value: errors.append(message)
    check(not assets['failures'], 'Asset conversion failures present')
    check(set(assets['weapons'])==set(catalog['weapons']), 'Missing original weapon assets')
    for path, provenance in assets['provenance'].items():
        raw = tre.read(path)
        check(hashlib.sha256(raw).hexdigest()==provenance['sha256'], 'Source hash mismatch: '+path)
    for key, profile in catalog['weapons'].items():
        path = ROOT/'vendor/Core3/MMOCoreORB/bin/scripts'/profile['source_file']
        check(hashlib.sha256(path.read_bytes()).hexdigest()==profile['source_sha256'], 'Core3 source hash mismatch: '+key)
        check(parse_template(path)==profile['core3'], 'Core3 statistics changed: '+key)
        check('attackSpeed' not in profile['core3'], 'Legacy attack speed retained')
        if profile.get('kind')=='melee':
            record=assets['weapons'][key]
            # Audit against the source VTXA positions, not only a hash of the
            # input file: an importer unit conversion can preserve provenance
            # while silently enlarging the rendered weapon.
            for part in record['parts']:
                converted=json.loads((directory/assets['meshes'][part['mesh']]['path']).read_text())
                source=parse_iff(tre.read(part['mesh']))
                surfaces=[]
                for surface in source.first('SPS ').children[0].children:
                    if not surface.children: continue
                    vtx=surface.first('VTXA'); _,count=struct.unpack('<II',vtx.first('INFO').data)
                    if not count or not struct.unpack_from('<I',surface.first('INDX').data)[0]: continue
                    raw=vtx.first('DATA').data; stride=len(raw)//count
                    points=[struct.unpack_from('<3f',raw,i*stride) for i in range(count)]
                    surfaces.append([v for x,y,z in points for v in (x,y,-z)])
                check(surfaces==[s['vertices'] for s in converted['surfaces']],
                      'Melee geometry differs from source dimensions/positions: '+key)
            events={}
            for node in parse_iff(tre.read(record['client_data'])).walk('CEFT'):
                name,pos=cstring(node.data);source,_=cstring(node.data,pos)
                if name in ('swing','hit'): events[name]=source
            check(record['effects']==events, 'Melee events differ from original CDF: '+key)
        else:
            check(assets['weapons'][key]['muzzle'][2]<0, 'Muzzle must be forward: '+key)
    class SourceReader:
        def read(self,path): return tre.read(path)
    for race,definition in assets['stow_mounts'].items():
        model_path=ROOT/'runtime/assets/characters'/definition['model']
        raw=model_path.read_bytes()
        check(hashlib.sha256(raw).hexdigest()==definition['model_sha256'], 'Avatar skeleton provenance changed: '+race)
        expected=bake(SourceReader(),json.loads(raw),{'hip':30,'back':50})
        for mount,data in definition['mounts'].items():
            check(data==expected[mount], 'Stow transform differs from original sampled animation: '+race+'/'+mount)
            for field in ['matrix','left_matrix']:
                matrix=[data[field][i:i+4] for i in range(0,12,4)]
                orthogonal=all(abs(sum(matrix[k][i]*matrix[k][j] for k in range(3))-(1 if i==j else 0))<1e-5 for i in range(3) for j in range(3))
                determinant=sum(matrix[0][i]*(matrix[1][(i+1)%3]*matrix[2][(i+2)%3]-matrix[1][(i+2)%3]*matrix[2][(i+1)%3]) for i in range(3))
                check(orthogonal and determinant>0.9999,'Mirrored mount must preserve proper gun orientation: '+race+'/'+mount)
    for key,weapon in assets['weapons'].items():
        source=parse_iff(tre.read(weapon['attachment']['arrangement']))
        slots=[[v.decode('ascii') for v in node.data.split(b'\0') if v] for node in source.walk('ARG ')]
        check(slots==weapon['attachment']['slots'],'Original arrangement slots changed: '+key)
    for event in ('swing','hit'):
        check(assets['unarmed']['effects'][event]==f'clienteffect/combat_melee_{event}_unarmed.cef', 'Original unarmed effect reference changed')
    materials=[]
    for metadata in assets['meshes'].values():
        model=json.loads((directory/metadata['path']).read_text())
        materials.extend(model['surfaces'])
    for particle in assets['particles'].values():
        materials.extend(e['material'] for e in particle['emitters'])
    for material in materials:
        source=Image.open(io.BytesIO(tre.read(material['texture_source']))).convert('RGBA')
        converted=Image.open(directory/material['texture']).convert('RGBA')
        check(source.size==converted.size and source.tobytes()==converted.tobytes(), 'Texture pixels differ: '+material['texture_source'])
    for sound in assets['sounds'].values():
        for path in sound['samples']:
            with wave.open(str(directory/path),'rb') as audio:
                check(audio.getnframes()>0 and audio.getsampwidth()==2, 'Invalid lossless audio decode: '+path)
    report={'test':'combat_asset_provenance','passed':not errors,'checks':checks,'errors':errors,
            'weapons':len(assets['weapons']),'source_dependencies':len(assets['provenance']),
            'core3_revision':catalog['core3_revision'],'visual_parity_verified':False}
    output=ROOT/'runtime/evidence/combat-assets-validation.json'
    output.parent.mkdir(exist_ok=True,parents=True)
    output.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))
    raise SystemExit(1 if errors else 0)


if __name__=='__main__': main()
