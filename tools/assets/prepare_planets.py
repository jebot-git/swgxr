#!/usr/bin/env python3
"""Reconstruct supported original ground worlds from local media, resumably.

Every converter records hashes and limitations. No placeholders, replacement
assets, Lua execution, local spawned authority or synthetic travel rules.
"""
import argparse, hashlib, json, subprocess, sys, time
from pathlib import Path
from planet_config import PLANETS, ROOT, origin_for, path_for
from swg_formats import TreSet
from prepare_services import travel_points

CONVERTER_FILES=sorted(p for p in (ROOT/"tools/assets").glob("*.py") if not p.name.startswith(("test_","validate_")) and p.name not in ("prepare_planets.py","complete_planet_features.py"))+[ROOT/"tools/server/export_ambient_npcs.py",ROOT/"tools/server/export_combat_population.py"]

def pipeline_hash():
    return hashlib.sha256(b"".join(p.name.encode()+p.read_bytes() for p in CONVERTER_FILES)).hexdigest()

def sources_current(path, tre):
    try:
        doc=json.loads(path.read_text());provenance=doc.get("provenance",{})
        for name,record in provenance.get("dependencies",{}).items():
            if hashlib.sha256(tre.read(name)).hexdigest()!=record["sha256"]:return False
        for name,record in provenance.get("files_sha256",{}).items():
            source=Path(name) if Path(name).is_absolute() else ROOT/name
            digest=record.get("sha256") if isinstance(record,dict) else record
            if not source.is_file() or hashlib.sha256(source.read_bytes()).hexdigest()!=digest:return False
        return True
    except (OSError,ValueError,KeyError,TypeError):return False



def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp=path.with_suffix('.tmp');tmp.write_text(json.dumps(data,indent=2)+'\n');tmp.replace(path)


def descriptor(planet):
    root=ROOT/'runtime/assets/planets'/planet
    row=dict(planet=planet,label=planet.title() if planet!='yavin4' else 'Yavin IV',origin=origin_for(planet),ready=False,failures=[])
    for key,component,file in [('terrain','terrain',planet+'.json'),('terrain_context','terrain','context.json'),('world','world','world.json'),('environment','environment','environment.json'),('services','services','catalog.json'),('ambient_npcs','ambient','catalog.json'),('ambient_placements','ambient','placements.json')]:
        row[key]=str(path_for(planet,component)/file)
    row['stage']=str(ROOT/'runtime/assets/mos_eisley/scene.json') if planet=='tatooine' else ''
    row['entities']=str(ROOT/'runtime/assets/combat_population/tatooine_entities/catalog.json') if planet=='tatooine' else str(root/'entities/catalog.json')
    row['trainers']=str(path_for(planet,'services')/'trainers.json')
    row['datapad']=str(ROOT/'runtime/assets/datapad/catalog.json')
    row['inventory']=str(ROOT/'runtime/assets/inventory/catalog.json')
    row['corpses']=str(ROOT/'runtime/assets/corpses/catalog.json')
    row['travel_points']=travel_points(ROOT/'vendor/Core3',{},planet)
    row['default_entry']=next((p for p in row['travel_points'] if p['interplanetary']),row['travel_points'][0])['position']
    return row


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--planets',nargs='+',choices=PLANETS,default=list(PLANETS))
    ap.add_argument('--tre-dir',type=Path,default=ROOT/'runtime/asset_sources/active_tre')
    ap.add_argument('--catalog-only',action='store_true')
    ap.add_argument('--force',action='store_true')
    ap.add_argument('--skip-entities',action='store_true',help='Diagnostic terrain/static pass; does not declare full feature readiness')
    args=ap.parse_args();out=ROOT/'runtime/assets/planets';catalog=out/'catalog.json'
    data=json.loads(catalog.read_text()) if catalog.exists() else dict(schema_version=1,planets={},unsupported={})
    if 'tatooine' not in data['planets']:
        base=descriptor('tatooine');base['ready']=all(Path(base[k]).is_file() for k in ('terrain','terrain_context','world','environment','services','ambient_npcs','ambient_placements','entities'));data['planets']['tatooine']=base
    tre=TreSet(args.tre_dir);code_hash=pipeline_hash()
    state_path=out/'preparation_state.json'
    states=json.loads(state_path.read_text()) if state_path.exists() else {}
    for missing in ('kashyyyk','mustafar'):
        data['unsupported'][missing]={'ready':False,'reason':'Outside pinned pre-CU ground planet set; source terrain/snapshot missing from active user media','missing':[p for p in (f'terrain/{missing}.trn',f'snapshot/{missing}.ws') if p not in tre.entries]}
    for planet in args.planets:
        row={**data['planets'].get(planet,{}),**descriptor(planet)};data['planets'][planet]=row;write(catalog,data)
        steps=[('terrain','tools/assets/prepare_terrain.py',[]),('terrain_context','tools/assets/prepare_terrain_context.py',[]),('world','tools/assets/prepare_world.py',[]),('ambient_placements','tools/server/export_ambient_npcs.py',['--city','all','--out',str(path_for(planet,'ambient'))]),('ambient_npcs','tools/assets/prepare_npcs.py',['--out',str(path_for(planet,'ambient')),'--placements',row['ambient_placements'],'--merge']),('environment','tools/assets/prepare_environment.py',[]),('services','tools/assets/prepare_services.py',[]),('entities','tools/assets/prepare_planet_entities.py',['--out',str(Path(row['entities']).parent)])]
        for key,script,extra in steps:
            dest=Path(row[key]);log=out/'logs'/f'{planet}-{key}.log'
            if args.skip_entities and key in ('ambient_placements','ambient_npcs','entities'):continue
            stamp=states.get(planet+':'+key,{})
            # Legacy local outputs are adopted only after their recorded source
            # dependencies validate; subsequent converter changes invalidate them.
            valid=dest.is_file() and sources_current(dest,tre) and (not stamp or (stamp.get('converter_sha256')==code_hash and stamp.get('manifest_sha256')==hashlib.sha256(dest.read_bytes()).hexdigest()))
            if args.catalog_only:continue
            if valid and not args.force:
                states[planet+':'+key]={'converter_sha256':code_hash,'manifest_sha256':hashlib.sha256(dest.read_bytes()).hexdigest()}
                write(state_path,states);continue
            log.parent.mkdir(parents=True,exist_ok=True)
            command=[sys.executable,str(ROOT/script),'--tre-dir',str(args.tre_dir),*extra]
            if key!='ambient_npcs':command+=['--planet',planet]
            print(f'{planet}: {key}',flush=True)
            with log.open('w') as output:
                result=subprocess.run(command,stdout=output,stderr=subprocess.STDOUT)
            if result.returncode==0 and dest.is_file():
                states[planet+':'+key]={'converter_sha256':code_hash,'manifest_sha256':hashlib.sha256(dest.read_bytes()).hexdigest()};write(state_path,states)
            if result.returncode:row['failures'].append({'component':key,'returncode':result.returncode,'log':str(log)});write(catalog,data)
        required=('terrain','terrain_context','world','environment','services','ambient_placements','ambient_npcs','entities')
        for key in required:
            if not Path(row[key]).is_file():row['failures'].append({'component':key,'error':'Manifest not prepared'})
        row['ready']=not row['failures'] and bool(row.get('feature_coverage')) and Path(row['trainers']).is_file()
        row['components_ready']=not row['failures']
        row['files_sha256']={key:hashlib.sha256(Path(row[key]).read_bytes()).hexdigest() for key in required if Path(row[key]).is_file()}
        row['limitations']=['Original static and terrain reconstruction; native Core3 owns live entities and travel.','Existing material, flora, weather, day-length and unsupported-conversion limitations remain recorded in component manifests.']
        write(catalog,data)
        print(json.dumps({'planet':planet,'ready':row['ready'],'failures':row['failures']}),flush=True)
    if not args.catalog_only and not args.skip_entities:
        subprocess.run([sys.executable,str(ROOT/'tools/assets/prepare_datapad.py'),'--tre-dir',str(args.tre_dir)],check=True)
        subprocess.run([sys.executable,str(ROOT/'tools/assets/complete_planet_features.py'),'--planets',*args.planets],check=True)
        data=json.loads(catalog.read_text())
    return int(any(not data['planets'][p]['ready'] for p in args.planets))

if __name__=='__main__':raise SystemExit(main())
