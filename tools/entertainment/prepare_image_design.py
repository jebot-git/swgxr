#!/usr/bin/env python3
"""Export a compact source-derived policy for the private native image bridge."""
import argparse
import hashlib
import json
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path[:0]=[str(ROOT),str(ROOT/'server'),str(ROOT/'tools/assets')]
from server.image_design_catalog import definitions, options
from server.creation_catalog import hair_rules
from server.character_protocol import assets


def provenance():
    paths=['datatables/customization/'+name+'.iff' for name in ('customization_data','holoemotes','hair_assets_skill_mods','allow_bald','palette_columns')]
    paths += ['customization/asset_customization_manager.iff','customization/customization_id_manager.iff']
    result={name:hashlib.sha256(assets().read(name)).hexdigest() for name in paths}
    for name in ('runtime/assets/characters/catalog.json','server/image_design_catalog.py','server/creation_catalog.py','tools/entertainment/prepare_image_design.py'):
        result[name]=hashlib.sha256((ROOT/name).read_bytes()).hexdigest()
    return result


def build():
    rows, holo, characters=definitions()
    policies={}
    mods={key:100 for key in ('body','face','hair','markings')}
    master={'skills':['social_imagedesigner_master'],'skill_mods':mods}
    for race, source in characters['races'].items():
        appearance={'race':race,'customization':{},'hair':None}
        complete=options(master,appearance)
        controls=[]
        for control in complete['controls']:
            row=next(r for r in rows if r['SPECIES_GENDER']==race and r['CUSTOMIZATION_NAME']==control['id'])
            mod=row['IMAGEDESIGN_SKILLMOD'];branch={'body':'bodyform','face':'exotic','hair':'hairstyle'}.get(mod,mod)
            maxima=[]
            for tier in range(5):
                learned=[] if not tier else [f'social_imagedesigner_{branch}_0{tier}']
                selected=options({'skills':learned,'skill_mods':mods},appearance)
                maxima.append(next(c['max'] for c in selected['controls'] if c['id']==control['id']))
            maxima.append(control['max'])
            controls.append({'id':control['id'],'type':control['type'],'mod':mod,'required':row['SKILLMOD_VALUE'],'branch':branch,'maxima':maxima})
        valid_hair={h['template'] for h in complete['hair']}
        hair=[{'template':r['SERVER_TEMPLATE'],'required':r['SKILL_MOD_VALUE']} for r in hair_rules() if r['SERVER_PLAYER_TEMPLATE']==source['template'] and r['SERVER_TEMPLATE'] in valid_hair]
        policies[source['template']]={'race':race,'controls':controls,'hair':hair,'allow_bald':complete['allow_bald']}
    return {'schema_version':1,'races':policies,'holoemotes':[{'name':r['HOLOEMOTE'],'required':r['REQUIRED_HAIR_SKILLMOD']} for r in holo],
            'provenance':provenance()}


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--ensure',action='store_true');args=parser.parse_args()
    output=ROOT/'runtime/assets/image_design/policy.json';output.parent.mkdir(parents=True,exist_ok=True)
    if args.ensure and output.exists():
        try:
            previous=json.loads(output.read_text())
            if previous.get('schema_version')==1 and previous.get('provenance')==provenance():
                print('Image design policy is current.');return
        except (OSError,ValueError):pass
    value=build();temporary=output.with_suffix('.tmp');temporary.write_text(json.dumps(value,separators=(',',':')));temporary.replace(output)
    print(json.dumps({'races':len(value['races']),'controls':sum(len(v['controls']) for v in value['races'].values()),'policy':str(output)}))

if __name__=='__main__':main()
