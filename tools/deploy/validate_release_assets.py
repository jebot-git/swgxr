#!/usr/bin/env python3
"""Audit every prepared ground planet and referenced entity catalog, without a server.

This covers converted structure/provenance, not live spawns, encounters or VR.
Source omissions are retained separately from validator failures.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import subprocess
import sys
import time

ROOT=Path(__file__).resolve().parents[2]

def jobs(catalog):
    rows=[];directories={ROOT/'runtime/assets/characters'}
    for planet,row in catalog['planets'].items():
        environment=Path(row['environment'])
        rows.append((planet+'-environment',['tools/assets/validate_environment.py','--directory',str(environment.parent)]))
        rows.append((planet+'-interiors',['tools/assets/validate_interiors.py','--world',row['world'],'--environment',str(environment)]))
        directories.add(Path(row['ambient_npcs']).parent)
        directories.update(Path(p).parent for p in row['entity_catalogs'])
    for directory in sorted(directories):
        if json.loads((directory/'catalog.json').read_text()).get('races'):
            name=str(directory.relative_to(ROOT/'runtime/assets')).replace('/','-')
            rows.append((name+'-models',['tools/assets/validate_characters.py','--directory',str(directory)]))
    rows.extend((name,[script]) for name,script in (
        ('worlds','tools/assets/validate_planets.py'),
        ('player-animations','tools/assets/validate_animations.py'),
        ('inventory','tools/assets/validate_inventory.py'),
        ('corpses','tools/assets/validate_corpses.py'),
        ('datapad','tools/assets/validate_datapad.py'),
        ('combat-assets','tools/combat/validate_assets.py'),
        ('pet-assets','tools/pets/audit_assets.py'),
    ))
    return rows

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report-dir',type=Path,default=ROOT/'runtime/evidence/all-planets-release')
    parser.add_argument('--workers',type=int,default=2)
    parser.add_argument('--only',nargs='+',help='Rerun named failed checks')
    args=parser.parse_args()
    args.report_dir=args.report_dir.resolve()
    if not 1<=args.workers<=4:raise SystemExit('Use 1–4 asset validator workers.')
    args.report_dir.mkdir(parents=True,exist_ok=True)
    catalog=json.loads((ROOT/'runtime/assets/planets/catalog.json').read_text())
    selected=jobs(catalog)
    if args.only:
        unknown=set(args.only)-{name for name,_ in selected}
        if unknown:raise SystemExit('Unknown checks: '+','.join(sorted(unknown)))
        selected=[row for row in selected if row[0] in args.only]
    def run(row):
        name,command=row;start=time.monotonic();log=args.report_dir/(name+'.log')
        if name.endswith('-interiors'):command=command+['--output',str(args.report_dir/(name+'.json'))]
        try:
            with log.open('w') as stream:
                result=subprocess.run([sys.executable,*command],cwd=ROOT,stdout=stream,stderr=subprocess.STDOUT,timeout=600)
            status='passed' if result.returncode==0 else 'failed';code=result.returncode
        except subprocess.TimeoutExpired:status='timeout';code=None
        result={'name':name,'status':status,'exit_code':code,'seconds':round(time.monotonic()-start,2),'log':str(log.relative_to(ROOT) if log.is_relative_to(ROOT) else log)}
        print(json.dumps(result),flush=True);return result
    with ThreadPoolExecutor(max_workers=args.workers) as pool:results=list(pool.map(run,selected))
    report={'scope':'Offline converted assets and source provenance; no native runtime, GPU or headset validation',
        'passed':all(r['status']=='passed' for r in results),'checks':results,
        'declared_source_limitations':{p:r.get('source_asset_limitations',{}) for p,r in catalog['planets'].items()},
        'unsupported_planets':catalog.get('unsupported',{}),'live_spawned':False}
    (args.report_dir/'validation.json').write_text(json.dumps(report,indent=2)+'\n')
    return 0 if report['passed'] else 1

if __name__=='__main__':raise SystemExit(main())
