#!/usr/bin/env python3
"""Audit ground-world manifests and source-owned portal/geometry/map contracts."""
import argparse, hashlib, json, math
from pathlib import Path
from planet_config import ROOT, PLANETS, origin_for
from validate_world import validate as validate_world
from swg_formats import TreSet


def check(planet, row, geometry=True):
    checks=[]
    def require(ok, detail):
        if not ok: raise AssertionError(f'{planet}: {detail}')
        checks.append(detail)
    require(row['planet']==planet and row['origin']==origin_for(planet),'canonical planet and consistent origin')
    docs={k:json.loads(Path(row[k]).read_text()) for k in ('terrain','terrain_context','world','environment','services','ambient_placements','ambient_npcs','entities')}
    for k in ('world','environment','services','ambient_placements'):
        require(docs[k]['origin']==row['origin'],k+' coordinates agree')
    require(docs['terrain']['planet']==planet and docs['world']['planet']==planet and docs['environment']['planet']==planet and docs['services']['zone']==planet,'source world tags agree')
    require(bool(docs['world']['chunks']) and bool(docs['terrain']['layers']),'original streaming geometry and terrain rules available')
    require(all(p['zone']==planet for p in row['travel_points']),'travel source zones agree')
    require(row['default_entry'] in [p['position'] for p in row['travel_points']],'entry is an authored Core3 travel position')
    require(planet=='tatooine' or not docs['world']['existing_stage_object_ids'],'new planets do not suppress Tatooine object IDs')
    require(planet=='tatooine' or not docs['terrain_context']['interior_masks'],'new planets do not use foreign starport terrain masks')
    maps=json.loads((ROOT/'runtime/assets/datapad/catalog.json').read_text())
    require(planet in maps['maps'] and (ROOT/'runtime/assets/datapad'/maps['maps'][planet]['texture']).is_file(),'original planet map raster available')
    geometry_report=validate_world(Path(row['world']).parent) if geometry else {}
    return dict(planet=planet,passed=True,checks=checks,geometry=geometry_report)


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--planets',nargs='+',choices=PLANETS,default=list(PLANETS));ap.add_argument('--no-geometry',action='store_true');args=ap.parse_args()
    catalog=ROOT/'runtime/assets/planets/catalog.json';data=json.loads(catalog.read_text());results=[]
    for planet in args.planets:
        try:results.append(check(planet,data['planets'][planet],not args.no_geometry))
        except Exception as error:results.append(dict(planet=planet,passed=False,error=str(error)))
        print(json.dumps(results[-1]),flush=True)
    out=ROOT/'runtime/evidence/planets';out.mkdir(parents=True,exist_ok=True);(out/'asset_validation.json').write_text(json.dumps(results,indent=2)+'\n')
    return int(not all(r['passed'] for r in results))

if __name__=='__main__':raise SystemExit(main())
