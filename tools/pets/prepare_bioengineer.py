#!/usr/bin/env python3
"""Prepare original crafted-pet appearances without enabling or spawning planets."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from server.artisan_catalog import recipe_previews
from server.profession_catalog import catalog


def main():
    scripts=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts'
    out=ROOT/'runtime/assets/bioengineer';out.mkdir(parents=True,exist_ok=True)
    sources={};templates=set()
    def read(path):
        raw=path.read_bytes();sources[str(path.relative_to(ROOT))]=hashlib.sha256(raw).hexdigest();return raw.decode()
    for row in recipe_previews(ROOT/'vendor/Core3',catalog())['professions']['outdoors_bio_engineer']:
        if not row['template'].startswith('object/tangible/deed/pet_deed/'):continue
        deed=read(scripts/(row['template'].removesuffix('.iff')+'.lua'))
        name=re.search(r'\bmobileTemplate\s*=\s*"([^"]+)"',deed)[1]
        mobile=read(scripts/'mobile/pet'/(name+'.lua'))
        block=re.search(r'\btemplates\s*=\s*\{([^}]+)\}',mobile)[1]
        templates.update(re.findall(r'"(object/mobile/[^"]+)"',block))
    candidates=[ROOT/'runtime/assets'/path/'catalog.json' for path in ('combat_population/native_current','combat_population/tatooine','combat_population/tatooine_entities','ambient_npcs')]
    candidates+=sorted((ROOT/'runtime/assets/planets').glob('*/entities/catalog.json'))
    candidates.append(out/'pets/catalog.json')
    def index():
        result={}
        for path in candidates:
            if not path.exists():continue
            for template,record in json.loads(path.read_text()).get('races',{}).items():
                if template in templates and record.get('appearance_complete',True):result.setdefault(template,str(path.relative_to(ROOT)))
        return result
    prepared=index();missing=sorted(templates-prepared.keys())
    if missing:
        request=out/'appearance_requests.json'
        request.write_text(json.dumps({'schema_version':1,'mode':'appearance_requests_only_no_spawn_positions','instances':[{'template':t,'appearance_id':t,'mood':'neutral','mobile':''} for t in missing],'provenance':{'files_sha256':sources}},indent=2)+'\n')
        subprocess.run([sys.executable,str(ROOT/'tools/assets/prepare_npcs.py'),'--out',str(out/'pets'),'--placements',str(request),'--merge'],check=True)
        subprocess.run([sys.executable,str(ROOT/'tools/assets/refresh_npc_death_poses.py'),str(out/'pets')],check=True)
        prepared=index()
    report={'catalogs':prepared,'sources_sha256':sources,'missing':sorted(templates-prepared.keys()),'spawned_entities':False}
    (out/'appearance_catalogs.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({'bioengineer_pet_templates':len(templates),'prepared':len(prepared),'missing':report['missing']}))
    if report['missing']:raise SystemExit(1)

if __name__=='__main__':main()
