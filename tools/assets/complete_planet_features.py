#!/usr/bin/env python3
"""Prepare shared harvesting/lair assets and check every planet feature reference."""
import argparse, hashlib, json, subprocess, sys
from pathlib import Path
from planet_config import ROOT, PLANETS
from prepare_planets import write


def update_world_diagnostics(row):
    # Legacy distributions retain validated world data and catalogue coverage,
    # but omit developer reports. Missing reports must not erase prior findings
    # or pretend to be a new collision/conversion audit.
    folder=Path(row['world']).parent
    status={}
    for name,field in [('collision_report.json','collision_coverage'),('conversion_report.json','architecture_omissions')]:
        path=folder/name
        if path.is_file():
            report=json.loads(path.read_text())
            row[field]=report.get('counts',{}) if field=='collision_coverage' else [r for r in report.get('skipped_objects',[]) if r.get('template','').startswith('object/building/')]
            status[name]='report_present'
        else:
            status[name]='retained_previous_catalog' if field in row else 'unavailable'
    row['world_diagnostic_sources']=status


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--planets',nargs='+',choices=PLANETS,default=list(PLANETS));ap.add_argument('--index-only',action='store_true');args=ap.parse_args()
    catalog=ROOT/'runtime/assets/planets/catalog.json';data=json.loads(catalog.read_text())
    for planet in args.planets:
        row=data['planets'][planet];sources=Path(row['entities']).with_name('sources.json')
        if not sources.exists():continue
        logs=ROOT/'runtime/assets/planets/logs'
        if not args.index_only:
            logs.mkdir(parents=True,exist_ok=True)
            for key,command in [('lairs',[sys.executable,'tools/assets/prepare_inventory.py','--population-lairs',str(sources)]),('corpses',[sys.executable,'tools/assets/prepare_corpses.py','--planet',planet])]:
                print(planet,key,flush=True)
                with (logs/f'{planet}-{key}.log').open('w') as stream:
                    subprocess.run(command,cwd=ROOT,stdout=stream,stderr=subprocess.STDOUT)
        # Read shared catalogs after each conversion, keeping all previous planets.
        inv=json.loads((ROOT/'runtime/assets/inventory/catalog.json').read_text());corpses=json.loads((ROOT/'runtime/assets/corpses/catalog.json').read_text())
        source=json.loads(sources.read_text());lairs=sorted({t for l in source['lairs'].values() for t in l['building_templates']})
        corpse_templates=corpses.get('planets',{}).get(planet,{}).get('templates',[])
        row['inventory']=str(ROOT/'runtime/assets/inventory/catalog.json');row['corpses']=str(ROOT/'runtime/assets/corpses/catalog.json');row['datapad']=str(ROOT/'runtime/assets/datapad/catalog.json');row['trainers']=str(Path(row['services']).with_name('trainers.json'))
        coverage_path=Path(row['entities']).with_name('coverage.json')
        coverage=json.loads(coverage_path.read_text()) if coverage_path.exists() else {}
        row['entity_catalogs']=sorted({str(ROOT/v['catalog']) for v in coverage.get('templates',{}).values() if v.get('catalog')})
        row['feature_coverage']={'lair_templates':len(lairs),'missing_lairs':[t for t in lairs if inv['items'].get(t,{}).get('status')!='ready'],'corpse_templates':len(corpse_templates),'missing_corpses':[t for t in corpse_templates if corpses['items'].get(t,{}).get('status')!='ready'],'entities':coverage.get('counts',{}),'trainer_manifest':Path(row['trainers']).is_file()}
        # Source omissions remain explicit limitations. Absent whole components
        # prevent loading, individual source conversion limitations don't invent art.
        if not Path(row['trainers']).is_file():row['failures'].append({'component':'trainers','error':'Missing trainer manifest'})
        required=('terrain','terrain_context','world','environment','services','ambient_npcs','ambient_placements','entities','trainers','datapad','inventory','corpses')
        row['ready']=not row['failures'] and all(Path(row[k]).is_file() for k in required)
        row['files_sha256']={key:hashlib.sha256(Path(row[key]).read_bytes()).hexdigest() for key in required if Path(row[key]).is_file()}
        terrain=json.loads(Path(row['terrain']).read_text());world=json.loads(Path(row['world']).read_text())
        unsupported={}
        def visit(layer):
            for group in ('boundaries','filters','affectors'):
                for rule in layer[group]:
                    if 'raw_hex' in rule:unsupported[rule['type']]=unsupported.get(rule['type'],0)+1
            for child in layer['children']:visit(child)
        for layer in terrain['layers']:visit(layer)
        row['terrain_rule_limitations']=unsupported
        update_world_diagnostics(row)
        row['source_asset_limitations']={'world':json.loads(Path(row['world']).read_text()).get('statistics',{}).get('conversion_failures',0),'entity_missing':coverage.get('counts',{}).get('missing',0),'entity_partial':coverage.get('counts',{}).get('partial',0),'corpses_missing':row['feature_coverage']['missing_corpses'],'lairs_missing':row['feature_coverage']['missing_lairs']}
        write(catalog,data);print(json.dumps({'planet':planet,'coverage':row['feature_coverage']}),flush=True)

if __name__=='__main__':main()
