#!/usr/bin/env python3
"""Export original performance audio and skeleton-compatible clips locally."""
import hashlib
import io
import json
from pathlib import Path
import sys
ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT), str(ROOT/'tools/assets'), str(ROOT/'tools/combat')]
from server.entertainment_catalog import catalog
from prepare_characters import CharacterImporter
from character_animations import load_lat, resolve, decode_clip
from prepare_assets import Assets
from prepare_inventory import InventoryImporter
from prepare_datapad import Elements
from character_formats import datatable
from PIL import Image

EFFECT_STEMS = {'dazzle':'dazzle', 'distract':'distract', 'spotlight':'spot_light',
                'colorlights':'color_lights', 'smokebomb':'smoke_bomb',
                'firejets':'fire_jets', 'ventriloquism':'ventriloquism'}

def prepare_effects(importer):
    """Keep original CEF/PRT data for the shared, bounded particle renderer."""
    failures = []
    rows = datatable(importer.read('datatables/performance/perform_effect.iff'))
    for row in rows:
        name = row['effectName'].lower()
        source = 'clienteffect/entertainer_'+EFFECT_STEMS[name[:-1]]+'_level_'+name[-1]+'.cef'
        try:
            importer.effect(source)
        except (ValueError, KeyError) as exc:
            failures.append({'source':source, 'phase':'special_effect', 'error':str(exc)})
    return failures

def main():
    out = ROOT/'runtime/entertainment'
    out.mkdir(parents=True, exist_ok=True)
    data = catalog()
    previous = json.loads((out/'catalog.json').read_text()) if (out/'catalog.json').exists() else {}
    data['provenance'].update(previous.get('provenance',{}))
    imp = Assets(ROOT/'runtime/assets/active_tre', out, bounded_particle_graphs=True)
    source_sounds = sorted({s for p in data['performances'].values() for s in p['sounds'].values()})
    failures = []
    for source in source_sounds:
        if not imp.audio_importer.sound(source): failures.append({'source':source, 'phase':'audio'})
    failures.extend(prepare_effects(imp))
    data['effects'] = imp.effects
    data['particles'] = imp.particles
    data['particle_limitations'] = [
        'Original quad curves and textures feed the shared bounded particle renderer.',
        'Nested attachment emitter motion is flattened; mesh particles are omitted and recorded per source.',
        'Dynamic CEF lights and camera shake are not played in XR.']
    data['sounds'] = imp.audio_importer.sounds
    data['provenance'].update(imp.dependencies)
    data['provenance'].update(imp.audio_importer.dependencies)
    print(json.dumps({'audio_definitions':len(data['sounds']), 'failures':failures}), flush=True)
    source = ROOT/'runtime/assets/characters'
    characters = json.loads((source/'catalog.json').read_text())
    animations = sorted({p['animation'] for p in data['performances'].values()})
    data['rigs'] = {}
    for race, descriptor in characters['races'].items():
        importer = CharacterImporter(ROOT/'runtime/assets/active_tre', out)
        model = json.loads((source/descriptor['body']).read_text())
        graph = model['animation_graph']
        _, lat = load_lat(importer, graph['lat_bindings'][0]['lat'])
        library = {}
        for animation in animations:
            for flourish in range(9):
                key = 'perform_'+animation+('_'+str(flourish) if flourish else '')
                cached = previous.get('rigs',{}).get(race,{}).get(key)
                if cached and (out/cached['path']).exists():
                    library[key] = cached
                    continue
                logical = 'skill_action_'+str(flourish) if flourish else 'loop_skill'
                try:
                    leaves = resolve(lat[logical], dict(graph['selectors'], skill=animation))
                    leaf = next(v for v in leaves if '_dnc_' in v['source'])
                    clip = decode_clip(importer, leaf['source'], model['bones'], {b['name']:i for i,b in enumerate(model['bones'])})
                    clip.update(loop=flourish==0, logical=logical, source_speed_scale=leaf.get('speed_scale',1))
                    raw = json.dumps(clip,separators=(',',':')).encode()
                    relative = 'animations/'+hashlib.sha256(raw).hexdigest()[:24]+'.json'
                    dest = out/relative
                    dest.parent.mkdir(exist_ok=True)
                    if not dest.exists(): dest.write_bytes(raw)
                    library[key] = {'path':relative, 'source':leaf['source'], 'length':clip['length']}
                except (ValueError, KeyError, StopIteration) as exc:
                    failures.append({'race':race, 'animation':key, 'phase':'animation', 'error':str(exc)})
        data['rigs'][race] = library
        data['provenance'].update(importer.dependencies)
        print(json.dumps({'rig':race,'clips':len(library)}), flush=True)
    inventory = InventoryImporter(ROOT/'runtime/assets/active_tre', out/'items')
    inventory.out.mkdir(parents=True, exist_ok=True)
    models = {}
    for template in data['items']:
        models[template] = inventory.convert(template)
        if models[template].get('status') != 'ready': failures.append({'template':template,'phase':'model','detail':models[template]})
    (inventory.out/'catalog.json').write_text(json.dumps({'items':models,'aliases':{}},separators=(',',':')))
    data['provenance'].update(inventory.character.dependencies)
    ui = imp.read('ui/ui_styles.inc')
    styles = {a.get('name','').lower():a for tag,a in Elements(ui.decode()).items if tag.lower()=='imagestyle'}
    data['icons'] = {}
    for command in ['startband','startmusic','startdance','stopmusic','stopdance','imagedesign',
                    'registerwithlocation','spotlight','colorlights','dazzle','distract','smokebomb','firejet','ventriloquism']:
        style = styles.get('group' if command=='startband' else command)
        if not style: failures.append({'icon':command,'phase':'icon'}); continue
        texture = 'texture/'+style['source'].split(':')[-1]+'.dds'
        raw = imp.read(texture)
        rect = tuple(map(int,style['sourcerect'].split(',')))
        Image.open(io.BytesIO(raw)).convert('RGBA').crop(rect).save(out/(command+'.png'))
        data['icons'][command] = command+'.png'
    data['provenance'].update(imp.dependencies)
    data['failures'] = failures
    (out/'catalog.json').write_text(json.dumps(data,separators=(',',':'))+'\n')
    print(json.dumps({'performances':len(data['performances']),'rigs':len(data['rigs']),'failures':len(failures)}), flush=True)

if __name__ == '__main__': main()
