#!/usr/bin/env python3
"""Audit original tameable creature appearances and animated head anchors locally."""
import hashlib
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
HEAD_ANCHORS = ('head','head_base','fambaa_head','muzzle','neck')
sys.path.insert(0,str(ROOT/'tools/assets'))
from swg_formats import TreSet
from character_formats import datatable


def audit():
    base = ROOT/'runtime/assets'
    manifests = [base/'combat_population/sources.json', *sorted((base/'planets').glob('*/entities/sources.json'))]
    planets = json.loads((base/'planets/catalog.json').read_text())['planets'] if (base/'planets/catalog.json').exists() else {}
    catalogs = {}
    source_hashes = {}
    mount_source = 'datatables/mount/valid_scale_range.iff'
    mount_raw = TreSet(ROOT/'runtime/asset_sources/active_tre').read(mount_source)
    source_hashes[mount_source] = hashlib.sha256(mount_raw).hexdigest()
    mount_appearances = {row['appearance_name'] for row in datatable(mount_raw)}
    creatures = []
    missing = []
    templates_seen = set()
    for manifest in manifests:
        data = json.loads(manifest.read_text())
        planet = 'tatooine' if manifest.parent.name == 'combat_population' else manifest.parent.parent.name
        candidates = [manifest.parent/'catalog.json', base/'combat_population/tatooine/catalog.json',
                      base/'combat_population/tatooine_entities/catalog.json',base/'combat_population/mos_eisley_easy/catalog.json',
                      base/'combat_population/native_current/catalog.json',base/'ambient_npcs/catalog.json']
        candidates.extend(Path(p) for p in planets.get(planet,{}).get('entity_catalogs',[]))
        for path in candidates:
            if path.exists() and path not in catalogs: catalogs[path] = json.loads(path.read_text())
        def taming_chance(name, trail=()):
            if name in trail or name not in data['mobiles']: return 0
            path = ROOT/data['mobiles'][name]['source']
            raw = path.read_bytes()
            source_hashes[str(path.relative_to(ROOT))] = hashlib.sha256(raw).hexdigest()
            text = raw.decode()
            match = re.search(r'\btamingChance\s*=\s*([0-9.]+)', text)
            if match: return float(match[1])
            parent = re.search(r'=\s*(\w+):new', text)
            return taming_chance(parent[1], (*trail,name)) if parent else 0
        for name, mobile in data['mobiles'].items():
            if taming_chance(name) <= 0: continue
            for template in mobile['appearance_templates']:
                if (planet,template) in templates_seen: continue
                templates_seen.add((planet,template))
                path = next((p for p in candidates if template in catalogs.get(p,{}).get('races',{})), None)
                if path is None:
                    missing.append({'planet':planet,'template':template,'phase':'appearance'}); continue
                descriptor = catalogs[path]['races'][template]
                model_path = path.parent/descriptor.get('body',descriptor.get('model',''))
                try:
                    raw_model = model_path.read_bytes()
                    model = json.loads(raw_model)
                except (OSError,ValueError) as error:
                    missing.append({'planet':planet,'template':template,'phase':'converted_model','error':str(error)})
                    continue
                names = [b['name'] for b in model['bones']]
                anchor = next((bone for bone in HEAD_ANCHORS if bone in names),'')
                head = names.index(anchor) if anchor else -1
                record = {'planet':planet,'template':template,'catalog':str(path.relative_to(ROOT)),
                          'model':str(model_path.relative_to(ROOT)), 'head_bone':head,
                          'appearance':descriptor['appearance'],'in_original_mount_scale_table':descriptor['appearance'] in mount_appearances,
                          'anchor_name':anchor,'model_sha256':hashlib.sha256(raw_model).hexdigest(),
                          'appearance_complete':descriptor.get('appearance_complete',True)}
                creatures.append(record)
                if head < 0: missing.append({**record,'phase':'head_anchor'})
                if not record['appearance_complete']: missing.append({**record,'phase':'partial_appearance','failures':descriptor.get('appearance_failures',[])})
    ambient = json.loads((base/'ambient_npcs/catalog.json').read_text())
    placements = json.loads((base/'ambient_npcs/placements.json').read_text())
    trainers = []
    for row in placements['instances']:
        if row.get('mobile') != 'trainer_creaturehandler': continue
        key = row.get('appearance_id',row['template'])
        descriptor = ambient.get('races',{}).get(key,{})
        trainers.append({'id':row['id'],'appearance_id':key,'prepared':bool(descriptor),
                         'complete':descriptor.get('appearance_complete',False)})
    commands = ROOT/'vendor/Core3/MMOCoreORB/src/server/zone/objects/creature/commands'
    for name in ('TameCommand.h','EmboldenpetsCommand.h','EnragepetsCommand.h'):
        path = commands/name
        source_hashes[str(path.relative_to(ROOT))] = hashlib.sha256(path.read_bytes()).hexdigest()
    for path in (ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/managers/pet_manager.lua',
                 ROOT/'vendor/Core3/MMOCoreORB/src/server/zone/managers/creature/PetManagerImplementation.cpp'):
        source_hashes[str(path.relative_to(ROOT))] = hashlib.sha256(path.read_bytes()).hexdigest()
    return {'source':'Original Core3 spawn definitions and user-provided converted media; no live entities created',
            'creatures':creatures,'missing':missing,'trainers':trainers,'source_hashes':source_hashes,
            'head_anchor':'skeleton.global_transform * skeleton.get_bone_global_pose(head_index).origin; already includes animation and creature scale'}


if __name__ == '__main__':
    report = audit()
    out = ROOT/'runtime/pets'
    out.mkdir(parents=True,exist_ok=True)
    (out/'asset-audit.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({'creature_appearances_by_planet':len(report['creatures']),'unique_templates':len({c['template'] for c in report['creatures']}),
                      'missing':len(report['missing']),'trainers':report['trainers']}))
