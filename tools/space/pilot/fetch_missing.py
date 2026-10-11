#!/usr/bin/env python3
"""Fetch only missing open-source mission tables from the pinned reference commit.
Does not fetch client media. Records hashes and failed references separately.
"""
import concurrent.futures
import hashlib
import json
import urllib.error
import urllib.request
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
COMMIT='e3aac29b55b46fec2ce2b1518db80a8f70d798a5'
p=ROOT/'runtime/reference/pilot-progression'
report=json.loads((ROOT/'runtime/server/pilot-source/quests.json').read_text())
sources=json.loads((p/'sources.json').read_text())
refs=[key for key,error in report['errors'].items() if 'No such file' in error]
def fetch(key):
    kind,name=key.split(':');path=f'sku.0/sys.server/compiled/game/datatables/spacequest/{kind}/{name}.tab'
    url=f'https://raw.githubusercontent.com/SWG-Source/dsrc/{COMMIT}/{path}'
    try:
        raw=urllib.request.urlopen(url,timeout=30).read()
        dest=p/'quest_tables'/kind/(name+'.tab');dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(raw)
        return {'path':path,'url':url,'sha256':hashlib.sha256(raw).hexdigest()}
    except urllib.error.HTTPError as error:
        return {'reference':key,'url':url,'error':str(error)}
with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:results=list(pool.map(fetch,refs))
existing={s['path'] for s in sources}
sources.extend(r for r in results if 'path' in r and r['path'] not in existing)
(p/'sources.json').write_text(json.dumps(sources,indent=2)+'\n')
(p/'missing-tables.json').write_text(json.dumps([r for r in results if 'error' in r],indent=2)+'\n')
print(json.dumps({'fetched':sum('path' in r for r in results),'missing':sum('error' in r for r in results)}))
