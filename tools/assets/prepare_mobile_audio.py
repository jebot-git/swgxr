#!/usr/bin/env python3
"""Original vehicle, creature and NPC CDF combat audio; local assets only."""
import argparse
import hashlib
import json
import struct
from pathlib import Path
from prepare_environment import EnvironmentImporter
from swg_formats import parse_iff, cstring

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'runtime/assets/mobile_audio'


def sound_bindings(raw, vehicle=False):
    tree = parse_iff(raw)
    if vehicle:
        # Keep the original damage bands and exact sound slot order.
        bands = []
        for node in tree.walk('VTHR'):
            damage = struct.unpack('<f', node.first('INFO').data)[0]
            sounds = []
            for record in node.walk('VSND'):
                values = []; offset = 0
                while offset < len(record.data):
                    value, offset = cstring(record.data, offset); values.append(value)
                assert len(values) in (9,), ('Unsupported VSND layout', len(values))
                sounds.append(dict(zip(('hardpoint', 'idle', 'accel', 'decel', 'run',
                                        'damage_idle', 'damage_accel', 'damage_decel', 'damage_run'), values)))
            bands.append({'damage': damage, 'sounds': sounds})
        assert bands, 'Missing vehicle thruster sound data'
        return {'kind': 'vehicle', 'bands': sorted(bands, key=lambda b: b['damage'])}
    events = {}
    for node in tree.walk('CSND'):
        event, offset = cstring(node.data); sound, end = cstring(node.data, offset)
        assert end == len(node.data)
        events[event] = sound
    return {'kind': 'droid', 'ambient': [cstring(n.data)[0] for n in tree.walk('ASND')], 'events': events}


def client_binding(imp, source):
    raw = imp.read(source)
    binding = sound_bindings(raw)
    binding['effects'] = {}
    for node in parse_iff(raw).walk():
        if node.tag not in ('CEFT','EVNT'):continue
        event, offset = cstring(node.data)
        effect, _ = cstring(node.data, offset)
        try:
            # CEFT is a general event binding: original CDFs also put SNDs here.
            binding['effects'][event] = [effect] if effect.endswith('.snd') else [cstring(n.data)[0] for n in parse_iff(imp.read(effect)).walk('PSND')]
        except Exception as error:
            imp.failures.append({'source': effect, 'cdf': source, 'event': event, 'error': str(error)})
    return binding


def sources(binding):
    if binding['kind'] == 'vehicle':
        return {value for band in binding['bands'] for row in band['sounds']
                for key, value in row.items() if key != 'hardpoint' and value}
    return set(binding['ambient']) | set(binding['events'].values()) | {sound for sounds in binding.get('effects', {}).values() for sound in sounds}


def main():
    parser = argparse.ArgumentParser(description=__doc__); parser.add_argument('--ensure', action='store_true'); args = parser.parse_args()
    paths = [Path(__file__), ROOT/'tools/assets/prepare_environment.py', ROOT/'runtime/assets/vehicles/catalog.json', ROOT/'runtime/assets/services/catalog.json', ROOT/'runtime/assets/combat/assets.json',
             *sorted((ROOT/'runtime/asset_sources/active_tre').glob('*.tre'))]
    signature = hashlib.sha256(json.dumps([(str(p.relative_to(ROOT)), p.stat().st_size, p.stat().st_mtime_ns) for p in paths]).encode()).hexdigest()
    target = OUT/'catalog.json'
    if args.ensure and target.exists():
        prior = json.loads(target.read_text())
        if prior.get('signature') == signature and all((OUT/p).is_file() for d in prior['sounds'].values() for p in d['samples']):
            print('Original mobile audio ready:',len(prior['templates']),'templates'); return
    imp = EnvironmentImporter(ROOT/'runtime/asset_sources/active_tre', OUT)
    templates = {}; bindings = {}
    vehicles = json.loads((ROOT/'runtime/assets/vehicles/catalog.json').read_text())
    for template, descriptor in vehicles['items'].items():
        source = descriptor['source_saddle']['client_data_filename']
        try:
            bindings.setdefault(source, sound_bindings(imp.read(source), True))
            templates[template] = source
        except Exception as error: imp.failures.append({'source':source,'template':template,'error':str(error)})
    # Exact original shared-template inheritance, including player-crafted droids.
    for shared in sorted(imp.t.entries):
        if not shared.startswith(('object/mobile/','object/creature/player/')) or '/shared_' not in shared or not shared.endswith('.iff'): continue
        try:
            source = imp.properties(shared).get('clientDataFile','')
            if not source or source not in imp.t.entries: continue
            if source not in bindings: bindings[source] = client_binding(imp, source)
            bindings[source]['kind'] = 'droid' if source.startswith('clientdata/droid/') else 'creature'
            templates[shared.replace('/shared_', '/')] = source
        except Exception as error: imp.failures.append({'source':shared,'error':str(error)})
    # Original shuttle animation messages resolve through CDF CSND/CEFT PSND.
    services = json.loads((ROOT/'runtime/assets/services/catalog.json').read_text())
    for template, descriptor in services['races'].items():
        source = descriptor['source_cdf']; tree = parse_iff(imp.read(source))
        binding = sound_bindings(imp.read(source)); binding['kind'] = 'shuttle'
        for node in tree.walk('CEFT'):
            event, offset = cstring(node.data); effect, _ = cstring(node.data, offset)
            sounds = [cstring(n.data)[0] for n in parse_iff(imp.read(effect)).walk('PSND')]
            if sounds: binding['events'][event] = sounds[0]
        binding['clips'] = {}
        for phase, clip in descriptor['clips'].items():
            messages = []
            for node in parse_iff(imp.read(clip['source'])).walk('MESG'):
                count = struct.unpack_from('<H', node.data)[0]
                message, offset = cstring(node.data, 2)
                assert len(node.data)-offset == count*2, 'Unsupported shuttle animation message frames'
                event = message.rsplit('_', 1)[-1]
                if event not in binding['events']: continue
                for frame in struct.unpack_from('<'+'H'*count,node.data,offset):
                    messages.append({'seconds':frame/clip['fps'],'event':event,'message':message})
            binding['clips'][phase] = sorted(messages,key=lambda row:row['seconds'])
        bindings[source] = binding; templates[template] = source
    weapon_sounds = {}
    combat = json.loads((ROOT/'runtime/assets/combat/assets.json').read_text())
    for weapon in combat['weapons'].values():
        effect = combat.get('effects', {}).get(weapon.get('effects', {}).get('fire', ''), {})
        sounds = effect.get('sounds', [])
        if sounds: weapon_sounds[weapon['shared_template'].replace('/shared_', '/')] = sounds[0]
    for sound in sorted(set(weapon_sounds.values())): imp.sound(sound)
    for sound in sorted(set().union(*(sources(binding) for binding in bindings.values()))): imp.sound(sound)
    catalog = {'schema_version':1,'signature':signature,'templates':templates,'bindings':bindings,
               'weapon_sounds':weapon_sounds,'sounds':imp.sounds,'provenance':imp.dependencies,'failures':imp.failures,
               'policy':'Original CDF slots and SND samples. Prototype motion thresholds; no synthesized sounds or animation-message timing claim.'}
    target.write_text(json.dumps(catalog,indent=2)+'\n')
    print(json.dumps({'templates':len(templates),'bindings':len(bindings),'sounds':len(imp.sounds),'failures':imp.failures}))


if __name__ == '__main__': main()
