#!/usr/bin/env python3
"""Export private native collision extents from the rendered original sectors."""
import argparse,hashlib,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def prepare(source,target):
    catalog=json.loads((source/'catalog.json').read_text());sectors={};hashes={}
    for zone,row in catalog['sectors'].items():
        path=source/row['descriptor'];data=json.loads(path.read_text());values=[]
        for field in data.get('asteroidfield',[]):
            if 'collision_spheres' not in field:raise ValueError('Reprepare sectors with collision extents: '+zone)
            values.extend(field['collision_spheres'])
        sectors[zone]=values;hashes[zone]=hashlib.sha256(path.read_bytes()).hexdigest()
    target.parent.mkdir(parents=True,exist_ok=True)
    target.write_text(json.dumps(dict(schema_version=1,sectors=sectors,source_sha256=hashes),separators=(',',':')))
    print(json.dumps(dict(sectors=len(sectors),asteroids=sum(map(len,sectors.values())),path=str(target))))
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--source',type=Path,default=ROOT/'runtime/assets/jtl');p.add_argument('--out',type=Path,default=ROOT/'vendor/Core3/MMOCoreORB/bin/conf/swgxr-space-collision.json');args=p.parse_args();prepare(args.source,args.out)
