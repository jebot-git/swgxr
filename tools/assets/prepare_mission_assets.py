#!/usr/bin/env python3
"""Prepare the complete original delivery-NPC union and mission item models.

Uses supplied local media only; grants/spawns no native objects. Re-running is
cheap when the exact original meshes are present. No substitute humanoids.
"""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]


def main():
    source = ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/mobile/mission/deliver_npc.lua'
    recipes = ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/managers/mission/mission_manager.lua'
    templates = sorted(set(re.findall(r'"(object/mobile/[a-z0-9_/]+\.iff)"', source.read_text())))
    outputs = sorted(set(re.findall(r'"(object/draft_schematic/item/quest_item/[a-z0-9_]+\.iff)"', recipes.read_text())))
    if not templates or not outputs:
        raise ValueError('Original mission NPC and crafting source definitions are required')
    items = ['object/tangible/mission/mission_datadisk.iff'] + [p.replace('draft_schematic/item/', 'tangible/mission/') for p in outputs]
    directory = ROOT/'runtime/assets/ambient_npcs'
    directory.mkdir(parents=True,exist_ok=True)
    def read(path):
        return json.loads(path.read_text()) if path.is_file() else {}
    def npc_ready(row):
        return bool(row.get('body')) and all((directory/entry).is_file() for entry in [row['body']]+[p['model'] for p in row.get('default_outfit',[])])
    catalog = read(directory/'catalog.json')
    missing = [t for t in templates if not npc_ready(catalog.get('races',{}).get(t,{}))]
    if missing:
        manifest = directory/'mission_source_templates.json'
        manifest.write_text(json.dumps({'instances':[{'id':'mission_template_'+str(i),'template':t,'mobile':'deliver_npc','mood':'neutral'} for i,t in enumerate(missing)],
            'source_policy':'Original dynamic mission appearance dependencies only; not world placements.',
            'provenance':{'files_sha256':{str(source.relative_to(ROOT)):hashlib.sha256(source.read_bytes()).hexdigest()}}},indent=2)+'\n')
        subprocess.run([sys.executable,str(ROOT/'tools/assets/prepare_npcs.py'),'--placements',str(manifest),'--merge'],check=True,cwd=ROOT)
    inventory = ROOT/'runtime/assets/inventory'
    item_catalog = read(inventory/'catalog.json')
    missing_items = [t for t in items if item_catalog.get('items',{}).get(t,{}).get('status')!='ready' or not (inventory/item_catalog['items'][t].get('model','')).is_file()]
    if missing_items:
        args=[sys.executable,str(ROOT/'tools/assets/prepare_inventory.py')]
        for template in missing_items:args+=['--template',template]
        subprocess.run(args,check=True,cwd=ROOT)
    catalog=read(directory/'catalog.json');item_catalog=read(inventory/'catalog.json')
    failures=[t for t in templates if not npc_ready(catalog.get('races',{}).get(t,{}))]
    failures += [t for t in items if item_catalog.get('items',{}).get(t,{}).get('status')!='ready']
    report={'passed':not failures,'npc_templates':templates,'mission_items':items,'converted_npc_count':len(missing),'failures':failures,
            'source_hashes':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (source,recipes)}}
    (directory/'mission_coverage.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({'passed':report['passed'],'npc_templates':len(templates),'mission_items':len(items),'failures':failures}))
    return 0 if not failures else 1


if __name__=='__main__':raise SystemExit(main())
