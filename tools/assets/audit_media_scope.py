#!/usr/bin/env python3
"""Check conversion failures against all user-owned TTE archives, with original referrers."""
import argparse
from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path
import re
from swg_formats import TreSet

RESOURCE=re.compile(r'(?:object|appearance|clientdata|clienteffect|sound|sample|creature/sample|shader|texture|terrain|snapshot)/[a-z0-9_./-]+\.(?:iff|cdf|cef|snd|wav|mp3|ogg|lmg|mgn|msh|lod|apt|pob|prt|sht|dds|sat|trn|ws)',re.I)
CATALOG_NAMES={'catalog.json','coverage.json','outfit_report.json','animation_audio_report.json','assets.json'}

def audit(tre_dir, assets):
    tre=TreSet(tre_dir);failures=[];missing=defaultdict(list)
    for path in sorted(Path(assets).rglob('*.json')):
        if path.name not in CATALOG_NAMES:continue
        data=json.loads(path.read_text())
        if not isinstance(data,dict):continue
        for key,rows in data.items():
            if 'fail' not in key and 'missing' not in key:continue
            if not isinstance(rows,list):continue
            for row in rows:
                if not isinstance(row,dict):continue
                # Template is the server object, not the missing client resource.
                def references(value):
                    if isinstance(value,dict):return {k:references(v) for k,v in value.items() if k not in ('template','appearance_id','reward_id')}
                    if isinstance(value,list):return [references(v) for v in value]
                    return value
                relevant=references(row)
                refs=sorted(set(s.lower() for s in RESOURCE.findall(json.dumps(relevant))))
                absent=[s for s in refs if s not in tre.entries]
                item={'catalog':path.relative_to(assets).as_posix(),'detail':row,'absent_references':absent,
                      'classification':'missing_reference' if absent else 'conversion_or_preparation_limitation'}
                failures.append(item)
                for name in absent:missing[name].append(item['catalog'])
    origins=defaultdict(list)
    pattern=re.compile(b'|'.join(re.escape(n.encode()) for n in missing)) if missing else None
    scanned=0
    if pattern:
        for name in tre.entries:
            if Path(name).suffix not in ('.cdf','.snd','.iff','.trn','.ws','.pob','.lmg','.apt','.cmp','.sat','.sht'):continue
            raw=tre.read(name).lower();scanned+=1
            for match in set(pattern.findall(raw)):origins[match.decode()].append(name)
    expansion=[n for n in tre.entries if (n.startswith('terrain/') and n.endswith('.trn') or n.startswith('snapshot/') and n.endswith('.ws')) and 'kashyyyk' in n]
    return {'schema':1,'scope':'Original game, Jump to Lightspeed and Rage of the Wookiees; later expansions not required',
            'archives':[{'name':p.name,'sha256':hashlib.file_digest(p.open('rb'),'sha256').hexdigest()} for p in tre.archives],
            'resource_count':len(tre.entries),'kashyyyk_roots_present':sorted(expansion),
            'original_resources_scanned_for_referrers':scanned,'failure_counts':dict(Counter(x['classification'] for x in failures)),
            'missing':[{'resource':n,'catalogs':sorted(set(c)),'original_referrers':sorted(origins[n])} for n,c in sorted(missing.items())],
            'failures':failures,
            'limits':['Failure audit covers the prepared feature catalogs, not a proof that every expansion dependency renders.',
                      'An original reference proves an authored dependency, not that a live scenario uses it.',
                      'Similar filenames are not treated as interchangeable. Retain original archives for future conversion.']}

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--tre-dir',type=Path,required=True);p.add_argument('--assets',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
    result=audit(a.tre_dir,a.assets);a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({'archives':len(result['archives']),'resources':result['resource_count'],'missing_unique':len(result['missing']),'failures':result['failure_counts'],'kashyyyk_roots':result['kashyyyk_roots_present']}))
