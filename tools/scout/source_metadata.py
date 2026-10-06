"""Original Ranger text, skill grants and camouflage kit definitions."""
import hashlib
import re
from pathlib import Path
from character_formats import datatable
from stf import string_table

ROOT=Path(__file__).resolve().parents[2]
COMMANDS=('conceal','rescue','areatrack','areatrack_animal','areatrack_npc','areatrack_player','areatrack_direction','areatrack_distance')


def build(read, inventory, provenance):
    tables={name:string_table(read('string/en/'+name+'.stf')) for name in ('cmd_n','cmd_d','skl_n','skl_d','skl_use','item_n','item_d','stat_d')}
    skills=[row for row in datatable(read('datatables/skill/skills.iff'))
            if row['NAME'].startswith('outdoors_ranger_')]
    kits={}
    failures=[]
    for path in sorted((ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/object/tangible/scout/camokit').glob('camokit_*.lua')):
        raw=path.read_bytes()
        key=str(path.relative_to(ROOT))
        provenance[key]={'sha256':hashlib.sha256(raw).hexdigest(),'bytes':len(raw)}
        zone=re.search(rb'effectiveZone\s*=\s*"([^"]+)"',raw)
        template='object/tangible/scout/camokit/'+path.stem+'.iff'
        item=inventory.get('items',{}).get(template,{})
        if not zone or item.get('status')!='ready':
            failures.append({'template':template,'phase':'camouflage_kit','error':'Missing native zone or original inventory model'})
        kits[template]={'effective_zone':zone[1].decode() if zone else '',
                        'label':tables['item_n'].get(path.stem,path.stem),
                        'description':tables['item_d'].get(path.stem,''),
                        'source_script':key,'inventory_model':item.get('model',''),
                        'model_sha256':item.get('model_sha256',''),'status':item.get('status','unavailable')}
    commands={key:{'label':tables['cmd_n'].get(key,key),'description':tables['cmd_d'].get(key,'')} for key in COMMANDS}
    descriptions={name:{key:value for key,value in table.items()
                        if key.startswith('outdoors_ranger_') or 'conceal' in key or key=='camouflage' or key=='rescue'}
                  for name,table in tables.items() if name in ('skl_d','skl_use','stat_d')}
    native=ROOT/'vendor/Core3/MMOCoreORB/src/server/zone/objects'
    for path in [native/'creature/commands'/name for name in ('ConcealCommand.h','RescueCommand.h','AreatrackCommand.h')]+[
                 native/'creature/ai/AiAgentImplementation.cpp',native/'creature/buffs/ConcealBuff.idl']:
        raw=path.read_bytes()
        provenance[str(path.relative_to(ROOT))]={'sha256':hashlib.sha256(raw).hexdigest(),'bytes':len(raw)}
    return {'commands':commands,'original_descriptions':descriptions,
            'ranger_skills':{row['NAME']:{'label':tables['skl_n'].get(row['NAME'],row['NAME']),
                                        'description':tables['skl_d'].get(row['NAME'],''),
                                        'commands':list(filter(None,row['COMMANDS'].split(','))),
                                        'skill_mods':row['SKILL_MODS']} for row in skills},
            'camouflage_kits':kits,'failures':failures}
