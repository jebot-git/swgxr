#!/usr/bin/env python3
"""Prepare original SWG item appearances for inventory previews; grants no items.

Incrementally accepts backend snapshots or explicit server/shared templates. All
converted game data remains under ignored runtime/assets, with source hashes.
"""
import argparse
import copy
import hashlib
import json
import re
from pathlib import Path

from character_formats import strings
from interior_layout import template_properties
from prepare_characters import CharacterImporter
from static_assets import StaticAssets
from swg_formats import cstring, parse_iff

ROOT = Path(__file__).resolve().parents[2]
GENERIC_BACKPACK = 'object/tangible/wearables/backpack/backpack_s01.iff'
GENERIC_NPC = 'object/mobile/shared_dressed_ranger_trainer_01.iff'


class PreviewCharacterImporter(CharacterImporter):
    def shader(self, path):
        root = parse_iff(self.read(path))
        if root.tag == 'OPST':
            alias = cstring(root.first('INFO').data)[0]
            raise ValueError('Owner-bound original OPST shader ' + path + ' (alias ' + repr(alias) + ') requires the owning character material; no arbitrary skin fallback was assigned')
        return super().shader(path)


class EquipmentCharacterImporter(CharacterImporter):
    def shader(self, path):
        root = parse_iff(self.read(path))
        if root.tag == 'OPST':
            alias = cstring(root.first('INFO').data)[0]
            material = getattr(self, 'owner_materials', {}).get(alias)
            if material is None and alias == 'body': material = getattr(self, 'skin_material', None)
            if material is None:
                raise ValueError('Original owner shader alias is not resolved for this wearable: ' + repr(alias))
            return {**copy.deepcopy(material), 'shader': path, 'resolved_skin_shader': material['shader']}
        return super().shader(path)


def canonical(template):
    template = template.lower().replace('\\', '/')
    if not re.fullmatch(r'object/[a-z0-9_/]+\.iff', template) or '..' in template:
        raise ValueError('Invalid inventory template path: ' + template)
    path = Path(template)
    name = path.name.removeprefix('shared_')
    return str(path.parent / name), str(path.parent / ('shared_' + name))


def snapshot_templates(value):
    """Accept the recursive backend inventory schema without assuming ownership."""
    result = set()
    if isinstance(value, dict):
        for key, child in value.items():
            if key in ('template', 'server_template', 'shared_template', 'object_template') and isinstance(child, str) and child.startswith('object/'):
                result.add(canonical(child)[0])
            else:
                result.update(snapshot_templates(child))
    elif isinstance(value, list):
        for child in value:
            result.update(snapshot_templates(child))
    return result


def snapshot_template_pairs(value):
    """Preserve actual Core3 shared-template mappings, including custom aliases."""
    result = {}
    if isinstance(value, dict):
        source = value.get('template', value.get('server_template', value.get('object_template')))
        shared = value.get('shared_template')
        if isinstance(source, str) and source.startswith('object/'):
            server, inferred = canonical(source)
            result[server] = canonical(shared)[1] if isinstance(shared, str) and shared.startswith('object/') else inferred
        elif isinstance(shared, str) and shared.startswith('object/'):
            server, shared = canonical(shared)
            result[server] = shared
        for child in value.values():
            if isinstance(child, (dict, list)):
                for server, shared in snapshot_template_pairs(child).items():
                    if server in result and result[server] != shared:
                        raise ValueError('Conflicting snapshot shared-template mappings: ' + server)
                    result[server] = shared
    elif isinstance(value, list):
        for child in value:
            for server, shared in snapshot_template_pairs(child).items():
                if server in result and result[server] != shared:
                    raise ValueError('Conflicting snapshot shared-template mappings: ' + server)
                result[server] = shared
    return result


def arrangements(read, source):
    if not source:
        return []
    root = parse_iff(read(source))
    if root.tag != 'ARGD':
        raise ValueError('Unsupported arrangement descriptor: ' + source)
    result = []
    for node in root.walk('ARG '):
        offset = 0; slots = []
        while offset < len(node.data):
            slot, offset = cstring(node.data, offset)
            slots.append(slot)
        result.append(slots)
    return result


def native_shared_templates(core3, requested, inputs, race_rules=None):
    """Follow literal native inheritance for custom loot aliases, without Lua execution."""
    clients = {}; parents = {}; registrations = {}; sources = {}; raw_hashes = {}; races = {}
    for source in sorted((core3/'MMOCoreORB/bin/scripts/object').rglob('*.lua')):
        raw = source.read_bytes(); text = re.sub(r'--[^\n]*', '', raw.decode())
        digest = hashlib.sha256(raw).hexdigest()
        for symbol, template in re.findall(r'ObjectTemplates:addClientTemplate\(\s*(\w+)\s*,\s*"(object/[a-z0-9_/]+\.iff)"', text):
            clients[symbol] = template; sources[symbol] = source; raw_hashes[source] = digest
        definitions = list(re.finditer(r'\b(\w+)\s*=\s*(\w+):new\s*\{', text))
        for index, definition in enumerate(definitions):
            symbol, parent = definition.groups()
            parents[symbol] = parent; sources[symbol] = source; raw_hashes[source] = digest
            body = text[definition.end():definitions[index+1].start() if index+1<len(definitions) else len(text)]
            block = re.search(r'\bplayerRaces\s*=\s*\{([^}]*)\}', body)
            if block:
                values = re.findall(r'"(object/[^"]+\.iff)"', block[1])
                if values or not block[1].strip(): races[symbol] = values
        for symbol, template in re.findall(r'ObjectTemplates:addTemplate\(\s*(\w+)\s*,\s*"(object/[a-z0-9_/]+\.iff)"', text):
            registrations[template] = symbol
    result = {}
    for template in requested:
        symbol = registrations.get(template); visited = set()
        while symbol and symbol not in visited:
            visited.add(symbol)
            if race_rules is not None and template not in race_rules and symbol in races:
                race_rules[template] = races[symbol]
            source = sources.get(symbol)
            if source: inputs[str(source.resolve())] = {'sha256':raw_hashes[source], 'kind':'Core3 loot shared-template inheritance'}
            if symbol in clients:
                result[template] = clients[symbol]; break
            symbol = parents.get(symbol)
    return result


class InventoryImporter:
    def __init__(self, tre_dir, out):
        self.out = out
        self.equipment_importers = {}
        self.equipment_bodies = {}
        self.character = PreviewCharacterImporter(tre_dir, out)
        self.static = StaticAssets(tre_dir, out)
        self.static.t = self.character.t
        # A single source-hash ledger covers both geometry/material paths.
        self.static.dependencies = self.character.dependencies
        self.read = self.character.read

    def generic_backpack(self):
        """Prove the fallback uses the same mesh as an original NPC wearable."""
        backpack_shared = canonical(GENERIC_BACKPACK)[1]
        bag = template_properties(self.read, backpack_shared)
        appearance = bag['appearanceFilename']
        meshes = strings(parse_iff(self.read(appearance)).first('MSGN').data)
        npc = template_properties(self.read, GENERIC_NPC)
        cdf = npc['clientDataFile']
        for index, wear in enumerate(parse_iff(self.read(cdf)).walk('WEAR')):
            for mesh in wear.walk('MESH'):
                original = cstring(mesh.data)[0]
                if original in meshes:
                    return {'template': GENERIC_BACKPACK, 'policy': 'Presentation bag only when no equipped backpack is supplied; does not grant a Core3 object',
                            'provenance': {'npc_shared_template': GENERIC_NPC, 'source_cdf': cdf, 'source_wear_index': index,
                                           'shared_mesh': original, 'backpack_shared_template': backpack_shared, 'backpack_appearance': appearance}}
        raise ValueError('Generic backpack no longer matches the original ranger NPC CDF wearable')

    def convert(self, template, shared_template=None):
        server, shared = canonical(template)
        if shared_template is not None:
            shared = canonical(shared_template)[1]
        descriptor = {'template': server, 'shared_template': shared, 'status': 'unsupported', 'failures': []}
        # Revisit component structure so a prior partially converted CMP cannot
        # bypass its recorded unsupported-child failure on another item.
        self.static.appearances.clear()
        before = len(self.static.failures)
        try:
            # Inheritance is required for common item templates with no local
            # appearance property. Do not infer a mesh from the item's name.
            properties = template_properties(self.read, shared)
            appearance = properties.get('inventoryAppearanceFilename') or properties.get('appearanceFilename')
            if not appearance:
                raise ValueError('No original inventory or world appearance in shared template')
            descriptor.update(appearance=appearance,
                              source_kind='inventory_appearance' if properties.get('inventoryAppearanceFilename') else 'appearance',
                              source_arrangement=properties.get('arrangementDescriptorFilename', ''),
                              held_transform=None)
            descriptor['source_arrangements'] = arrangements(self.read, descriptor['source_arrangement'])
            surfaces = []; meshes = []
            if appearance.endswith('.sat'):
                original = self.character.model(appearance)
                for part in original['parts']:
                    meshes.append(part['mesh']['source'])
                    for value in part['mesh']['surfaces']:
                        surface = copy.deepcopy(value)
                        for key in ('bones', 'weights', 'triangle_zones'):
                            surface.pop(key, None)
                        if server.startswith('object/mobile/vendor/'):
                            surface['bones']=[];surface['weights']=[]
                        else:surface.pop('blend_shapes',None)
                        surfaces.append(surface)
                descriptor.update(material_pipeline='original_character', pose_policy='original MGN bind-space vertices, frozen for item presentation; not an animated wearable')
            else:
                parts = self.static.resolve(appearance)
                for part in parts:
                    meshes.append(part['mesh'])
                    data = json.loads((self.out / self.static.meshes[part['mesh']]['path']).read_text())
                    surfaces.extend(data['surfaces'])
                descriptor.update(material_pipeline='original_static', pose_policy='original object-local static appearance; authored component transforms retained')
            if not surfaces:
                raise ValueError('Original appearance has no supported preview triangles')
            if any(not s.get('texture') or not (self.out / s['texture']).is_file() for s in surfaces):
                raise ValueError('An original surface diffuse texture could not be resolved')
            material_errors = [item for item in self.static.failures[before:] if item['phase'] in ('material', 'component_child')]
            if material_errors:
                raise ValueError('Incomplete original appearance: ' + repr(material_errors))
            points = [surface['vertices'][i:i + 3] for surface in surfaces for i in range(0, len(surface['vertices']), 3)]
            minimum = [min(p[i] for p in points) for i in range(3)]
            maximum = [max(p[i] for p in points) for i in range(3)]
            model = {'schema_version': 1, 'coordinate_system': 'Godot Y-up; original SWG Z mirrored; original object/bind origin retained',
                     'source_appearance': appearance, 'source_meshes': meshes, 'surfaces': surfaces,
                     'material_pipeline': descriptor['material_pipeline'], 'bounds_min': minimum, 'bounds_max': maximum}
            if server.startswith('object/mobile/vendor/'):
                model['blend_shapes']=sorted({name for surface in surfaces for name in surface.get('blend_shapes',{})})
                descriptor['vendor_morphs']=True
            encoded = json.dumps(model, separators=(',', ':')).encode()
            digest = hashlib.sha256(encoded).hexdigest()
            relative = 'models/' + digest[:24] + '.json'
            destination = self.out / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            # A material migration may have edited a cached file in place.
            # Content-addressed names must always match the bytes being indexed.
            if not destination.exists() or hashlib.sha256(destination.read_bytes()).hexdigest() != digest:
                destination.write_bytes(encoded)
            descriptor.update(status='ready', model=relative, model_sha256=digest, source_meshes=meshes,
                              bounds_min=minimum, bounds_max=maximum, vertices=len(points),
                              triangles=sum(len(surface['indices']) // 3 for surface in surfaces))
        except Exception as error:
            descriptor['failures'].append({'phase': 'inventory_appearance', 'error': str(error)})
        return descriptor

    def reusable_equipment(self, previous, shared, race_id):
        if previous.get('status') != 'ready' or previous.get('shared_template') != shared:
            return False
        path = self.out / previous.get('model', '')
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != previous.get('model_sha256'):
            return False
        if previous.get('kind') == 'rigid': return True
        character_dir = ROOT / 'runtime/assets/characters'
        if race_id not in self.equipment_bodies:
            race = json.loads((character_dir/'catalog.json').read_text())['races'][race_id]
            raw = (character_dir/race['body']).read_bytes()
            self.equipment_bodies[race_id] = (raw, json.loads(raw))
        return hashlib.sha256(self.equipment_bodies[race_id][0]).hexdigest() == previous.get('source_owner_model_sha256')

    def equipment(self, template, shared, race_id):
        """Original wearable bound to a prepared player rig, never preview geometry."""
        descriptor = {'template': template, 'shared_template': shared, 'race': race_id, 'status': 'unsupported', 'failures': []}
        try:
            character_dir = ROOT / 'runtime/assets/characters'
            characters = json.loads((character_dir / 'catalog.json').read_text())
            race = characters['races'][race_id]
            body_path = character_dir / race['body']
            if race_id not in self.equipment_bodies:
                raw = body_path.read_bytes()
                self.equipment_bodies[race_id] = (raw, json.loads(raw))
            body_raw, body = self.equipment_bodies[race_id]
            bones = copy.deepcopy(body['bones']); names = {bone['name']: index for index, bone in enumerate(bones)}
            properties = template_properties(self.read, shared)
            appearance = properties.get('appearanceFilename', '')
            descriptor.update(source_arrangement=properties.get('arrangementDescriptorFilename', ''))
            descriptor['source_arrangements'] = arrangements(self.read, descriptor['source_arrangement'])
            if not appearance.endswith('.sat'):
                visual = self.convert(template, shared)
                if visual['status'] != 'ready':
                    raise ValueError('Original rigid equipment unavailable: ' + repr(visual['failures']))
                descriptor.update({key: visual[key] for key in ('model', 'model_sha256', 'appearance', 'source_meshes', 'material_pipeline', 'bounds_min', 'bounds_max')})
                descriptor.update(status='ready', kind='rigid')
                return descriptor
            if race_id not in self.equipment_importers:
                prepared = EquipmentCharacterImporter(self.character.t.archives[0].parent, self.out, tre_set=self.character.t)
                prepared.dependencies = self.character.dependencies
                self.equipment_importers[race_id] = prepared
            importer = self.equipment_importers[race_id]
            body_surface = next((s for part in body['parts'] for s in part['mesh']['surfaces'] if '_body' in s['shader']), None)
            if body_surface is None:
                raise ValueError('Original player body shader binding unavailable')
            # Resolve owner-bound OPST clothing shaders from this actual race's
            # original body material; source palette controls remain per owner.
            importer.skin_material = importer.shader(body_surface['shader'])
            importer.owner_materials = {'body': importer.skin_material}
            # Twi'lek hats expose the owner's lekku, using a distinct original OPST alias.
            for alias in ('leccu', 'skull', 'face', 'eye', 'mouth', 'eyelash'):
                candidates = {surface['shader'] for part in body['parts'] for surface in part['mesh']['surfaces'] if surface['shader'].endswith('_'+alias+'.sht')}
                if len(candidates) == 1: importer.owner_materials[alias] = importer.shader(next(iter(candidates)))
            previous_count = len(bones)
            item = importer.wearable(shared, race_id, bones, names)
            model_path = self.out / item['model']
            model = json.loads(model_path.read_text())
            if len(bones) != previous_count:
                raise ValueError('Wearable needs additional virtual skin bones; existing tracked skeleton is retained')
            model['source_owner_shader'] = body_surface['shader']
            model['source_owner_model_sha256'] = hashlib.sha256(body_raw).hexdigest()
            encoded = json.dumps(model, separators=(',', ':')).encode()
            digest = hashlib.sha256(encoded).hexdigest()
            relative = 'equipment/' + race_id + '/' + digest[:24] + '.json'
            destination = self.out / relative; destination.parent.mkdir(parents=True, exist_ok=True)
            if not destination.exists() or hashlib.sha256(destination.read_bytes()).hexdigest() != digest: destination.write_bytes(encoded)
            descriptor.update(status='ready', kind='skinned', model=relative, model_sha256=digest,
                              appearance=item['appearance'], material_pipeline='original_character',
                              skeleton_bones=[bone['name'] for bone in body['bones']],
                              source_owner_shader=body_surface['shader'], source_owner_model=str(body_path),
                              source_owner_model_sha256=hashlib.sha256(body_raw).hexdigest())
        except Exception as error:
            descriptor['failures'].append({'phase': 'equipped_appearance', 'error': str(error)})
        return descriptor

    def owner_bound_preview(self, equipment, previous):
        """Freeze the resolved original wearable; do not invent an OPST material."""
        model = json.loads((self.out / equipment['model']).read_text())
        surfaces = []
        for part in model['parts']:
            for original in part['mesh']['surfaces']:
                surface = copy.deepcopy(original)
                for key in ('bones', 'weights', 'triangle_zones', 'blend_shapes'): surface.pop(key, None)
                surfaces.append(surface)
        points = [s['vertices'][i:i + 3] for s in surfaces for i in range(0, len(s['vertices']), 3)]
        minimum = [min(p[i] for p in points) for i in range(3)]
        maximum = [max(p[i] for p in points) for i in range(3)]
        data = {'schema_version': 1, 'coordinate_system': 'Godot Y-up; original SWG Z mirrored; original bind origin retained',
                'source_appearance': equipment['appearance'], 'source_meshes': [part['mesh']['source'] for part in model['parts']],
                'surfaces': surfaces, 'material_pipeline': 'original_character', 'bounds_min': minimum, 'bounds_max': maximum,
                'source_owner_shader': equipment['source_owner_shader'], 'owner_race': equipment['race']}
        raw = json.dumps(data, separators=(',', ':')).encode(); digest = hashlib.sha256(raw).hexdigest()
        relative = 'models/' + digest[:24] + '.json'
        (self.out / relative).write_bytes(raw)
        return {**previous, 'status': 'ready', 'failures': [], 'model': relative, 'model_sha256': digest,
                'appearance': equipment['appearance'], 'source_meshes': data['source_meshes'], 'bounds_min': minimum, 'bounds_max': maximum,
                'vertices': len(points), 'triangles': sum(len(s['indices']) // 3 for s in surfaces),
                'material_pipeline': 'original_character', 'owner_race': equipment['race'], 'source_owner_shader': equipment['source_owner_shader'],
                'pose_policy': 'Original race-resolved wearable bind vertices; OPST alias uses the original owning race body material'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tre-dir', type=Path, default=ROOT / 'runtime/asset_sources/active_tre')
    parser.add_argument('--out', type=Path, default=ROOT / 'runtime/assets/inventory')
    parser.add_argument('--template', action='append', default=[])
    parser.add_argument('--snapshot', type=Path, action='append', default=[])
    parser.add_argument('--loot-items', action='store_true', help='Prepare original ground loot item appearances from native loot definitions')
    parser.add_argument('--wearable-items', action='store_true', help='Prepare native clothing/armor registrations, including loot and crafted aliases')
    parser.add_argument('--all-equipment-races', action='store_true', help='Bind selected wearables to every prepared player rig')
    parser.add_argument('--starter-items', action='store_true', help='Prepare source creation-manager items as preview assets, never grant them')
    parser.add_argument('--gathering-assets', action='store_true', help='Prepare original Core3 survey tools and concrete resource-container templates; grants nothing')
    parser.add_argument('--spice-assets', action='store_true', help='Prepare all concrete original Core3 spice appearances for crafting previews; grants nothing')
    parser.add_argument('--population-lairs', type=Path, help='Prepare every original building/lair model referenced by a Core3 population sources.json dependency index')
    parser.add_argument('--core3-root', type=Path, default=ROOT / 'vendor/Core3')
    parser.add_argument('--refresh', action='store_true', help='Reconvert every existing catalog entry too')
    parser.add_argument('--equipment-race', action='append', default=[], help='Prepare original skinned equipment for this player race (e.g. human_male); snapshot race is also accepted')
    args = parser.parse_args()
    importer = InventoryImporter(args.tre_dir, args.out)
    path = args.out / 'catalog.json'
    catalog = json.loads(path.read_text()) if path.exists() else {'schema_version': 1, 'items': {}, 'aliases': {}, 'provenance': {'dependencies': {}, 'inputs': {}}}
    requested = {canonical(t)[0] for t in args.template} | {GENERIC_BACKPACK}
    pairs = {}
    race_rules = {}
    equipment_races = set(args.equipment_race)
    if args.all_equipment_races:
        equipment_races.update(json.loads((ROOT/'runtime/assets/characters/catalog.json').read_text())['races'])
    inputs = catalog['provenance'].setdefault('inputs', {})
    # Live readback files are routinely refreshed after real mutations. Preserve
    # their selection history without pretending an old state is still current.
    for source, record in list(inputs.items()):
        if record.get('kind', '').startswith('backend inventory snapshot') and 'selections' not in Path(source).parts:
            catalog['provenance'].setdefault('historical_selections', []).append({'source_path': source, **record})
            del inputs[source]
        elif args.population_lairs and record.get('kind') == 'Core3 population source definition' and Path(source).is_file() and hashlib.sha256(Path(source).read_bytes()).hexdigest()!=record['sha256']:
            # A fresh dependency selection below records current source hashes.
            # Preserve older selection evidence without claiming old Lua is current.
            catalog['provenance'].setdefault('historical_selections', []).append({'source_path':source,**record})
            del inputs[source]
    for snapshot in args.snapshot:
        raw = snapshot.read_bytes()
        snapshot_data = json.loads(raw)
        incoming = snapshot_template_pairs(snapshot_data)
        if isinstance(snapshot_data, dict) and isinstance(snapshot_data.get('race'), str): equipment_races.add(snapshot_data['race'])
        for template, shared in incoming.items():
            if template in pairs and pairs[template] != shared:
                raise ValueError('Conflicting shared templates across snapshots: ' + template)
        pairs.update(incoming)
        requested.update(incoming)
        digest = hashlib.sha256(raw).hexdigest()
        selection = args.out / 'selections' / (digest + '.json')
        selection.parent.mkdir(parents=True, exist_ok=True)
        if not selection.exists(): selection.write_bytes(raw)
        inputs[str(selection.resolve())] = {'sha256': digest, 'source_path': str(snapshot.resolve()), 'kind': 'backend inventory snapshot; immutable template-selection evidence, not an ownership store'}
    if args.population_lairs:
        raw = args.population_lairs.read_bytes()
        population = json.loads(raw)
        if population.get('mode') != 'source_dependency_index_not_live_population' or population.get('failures'):
            raise ValueError('Expected a complete Core3 population dependency index, not a live or inferred population')
        for relative, digest in population.get('provenance', {}).get('files_sha256', {}).items():
            source = ROOT / relative
            if hashlib.sha256(source.read_bytes()).hexdigest() != digest:
                raise ValueError('Population source changed; export the dependency index again: ' + relative)
            inputs[str(source.resolve())] = {'sha256': digest, 'kind': 'Core3 population source definition'}
        templates = sorted({canonical(template)[0] for lair in population['lairs'].values() for template in lair['building_templates']})
        requested.update(templates)
        digest = hashlib.sha256(raw).hexdigest()
        selection = args.out / 'selections' / (digest + '.json')
        selection.parent.mkdir(parents=True, exist_ok=True)
        if not selection.exists(): selection.write_bytes(raw)
        inputs[str(selection.resolve())] = {'sha256': digest, 'source_path': str(args.population_lairs.resolve()), 'kind': 'Core3 population dependency index; immutable reference selection, no spawned entities'}
        catalog['population_lairs'] = {'templates': templates, 'spawn_groups': sorted(population['spawn_groups']), 'source_sha256': digest,
                                       'policy': 'All building variants referenced by source lair definitions; original object origin/meters retained, no spawn authority'}
    if args.loot_items:
        references = set()
        for source in sorted((args.core3_root/'MMOCoreORB/bin/scripts/loot/items').rglob('*.lua')):
            if 'space' in source.parts: continue
            raw = source.read_bytes()
            text = re.sub(r'--[^\n]*', '', raw.decode())
            templates = re.findall(r'\bdirectObjectTemplate\s*=\s*"(object/[a-z0-9_/]+\.iff)"', text)
            references.update(templates)
            if templates: inputs[str(source.resolve())] = {'sha256':hashlib.sha256(raw).hexdigest(), 'kind':'Core3 ground loot appearance definition'}
        requested.update(references)
        pairs.update(native_shared_templates(args.core3_root, references, inputs))
        catalog['loot_assets'] = {'templates':sorted(references), 'policy':'Appearance dependencies only; loot eligibility, drops and ownership remain native server authority'}
    if args.wearable_items:
        references = set()
        for source in sorted((args.core3_root/'MMOCoreORB/bin/scripts/object/tangible/wearables').rglob('*.lua')):
            raw = source.read_bytes(); text = re.sub(r'--[^\n]*', '', raw.decode())
            templates = re.findall(r'ObjectTemplates:addTemplate\(\s*\w+\s*,\s*"(object/[a-z0-9_/]+\.iff)"', text)
            references.update(templates)
            if templates: inputs[str(source.resolve())] = {'sha256':hashlib.sha256(raw).hexdigest(), 'kind':'Core3 wearable appearance registration'}
        requested.update(references)
        pairs.update(native_shared_templates(args.core3_root, references, inputs, race_rules))
        # Do not advertise meshes for native-forbidden race/item pairs.
        for race, variants in catalog.get('equipment', {}).items():
            for template, allowed in race_rules.items():
                if allowed and 'object/creature/player/'+race+'.iff' not in allowed: variants.pop(template, None)
        catalog['wearable_assets'] = {'templates':sorted(references), 'races':sorted(equipment_races | set(catalog.get('equipment', {}))), 'race_restrictions':race_rules, 'policy':'Original rig-bound appearances; native species/equip restrictions remain authoritative'}
    if args.starter_items:
        source = args.core3_root / 'MMOCoreORB/bin/scripts/managers/player_creation_manager.lua'
        raw = source.read_bytes()
        # Literal declarations identify supported creation options, including
        # profession items. This does not claim each player owns every option.
        requested.update(re.findall(r'"(object/[a-z0-9_/]+\.iff)"', raw.decode()))
        inputs[str(source.resolve())] = {'sha256': hashlib.sha256(raw).hexdigest(), 'kind': 'Core3 player creation item definitions'}
    if args.gathering_assets:
        references = []
        for category in ('object/tangible/survey_tool', 'object/resource_container'):
            folder = args.core3_root / 'MMOCoreORB/bin/scripts' / category
            shared_source = folder / 'objects.lua'
            shared_raw = shared_source.read_bytes()
            shared_names = dict(re.findall(r'ObjectTemplates:addClientTemplate\(\s*(\w+)\s*,\s*"(object/[a-z0-9_/]+\.iff)"', shared_raw.decode()))
            inputs[str(shared_source.resolve())] = {'sha256': hashlib.sha256(shared_raw).hexdigest(), 'kind': 'Core3 original client-template mapping'}
            for source in sorted(folder.glob('*.lua')):
                if source.stem in ('objects', 'serverobjects', 'resource_spawn'): continue
                raw = source.read_bytes()
                templates = re.findall(r'ObjectTemplates:addTemplate\(\s*(\w+)\s*,\s*"(object/[a-z0-9_/]+\.iff)"', raw.decode())
                parents = dict(re.findall(r'\b(\w+)\s*=\s*(\w+):new\s*\{', raw.decode()))
                for symbol, template in templates:
                    requested.add(template); references.append(template)
                    parent = parents.get(symbol, '')
                    if parent in shared_names: pairs.setdefault(template, shared_names[parent])
                if templates:
                    inputs[str(source.resolve())] = {'sha256': hashlib.sha256(raw).hexdigest(), 'kind': 'Core3 survey tool/resource container reference template'}
        catalog['gathering_assets'] = {'templates': sorted(set(references)), 'policy': 'Reference appearances only; owned/deployed tools and gathered stacks remain authoritative server state'}
    if args.spice_assets:
        folder = args.core3_root / 'MMOCoreORB/bin/scripts/object/tangible/food/spice'
        shared_source = folder / 'objects.lua'
        shared_raw = shared_source.read_bytes()
        shared_names = dict(re.findall(r'ObjectTemplates:addClientTemplate\(\s*(\w+)\s*,\s*"(object/[a-z0-9_/]+\.iff)"', shared_raw.decode()))
        inputs[str(shared_source.resolve())] = {'sha256': hashlib.sha256(shared_raw).hexdigest(), 'kind': 'Core3 original spice client-template mapping'}
        references = []
        for source in sorted(folder.glob('spice_*.lua')):
            if source.stem == 'spice_base': continue
            raw = source.read_bytes()
            parents = dict(re.findall(r'\b(\w+)\s*=\s*(\w+):new\s*\{', raw.decode()))
            for symbol, template in re.findall(r'ObjectTemplates:addTemplate\(\s*(\w+)\s*,\s*"(object/[a-z0-9_/]+\.iff)"', raw.decode()):
                requested.add(template); references.append(template)
                if parents.get(symbol) in shared_names: pairs[template] = shared_names[parents[symbol]]
            inputs[str(source.resolve())] = {'sha256': hashlib.sha256(raw).hexdigest(), 'kind': 'Core3 concrete spice appearance reference'}
        catalog['spice_assets'] = {'templates': sorted(set(references)), 'policy': 'Original appearance references only; crafting availability and spice effects remain native server authority'}
    if args.refresh:
        requested.update(catalog['items'])
        if not equipment_races:
            equipment_races.update(item['owner_race'] for item in catalog['items'].values() if item.get('owner_race'))
    catalog['generic_backpack'] = importer.generic_backpack()
    for template in sorted(requested):
        shared = pairs.get(template, catalog['items'].get(template, {}).get('shared_template'))
        previous = catalog['items'].get(template, {})
        # Adding loot coverage must not replace an already owner-bound wearable
        # preview with an unbound conversion. Explicit refresh still rebuilds it.
        existing = args.out / previous.get('model', '')
        if args.loot_items and not args.refresh and previous.get('status') == 'ready' and existing.is_file() and hashlib.sha256(existing.read_bytes()).hexdigest() == previous.get('model_sha256'):
            descriptor = previous
        else:
            descriptor = importer.convert(template, shared)
        if args.loot_items and descriptor['status'] != 'ready' and 'Owner-bound original OPST' in str(descriptor.get('failures', [])) and template.startswith('object/tangible/wearables/'):
            race = previous.get('owner_race', 'wookiee_male' if 'kashyyykian' in template else 'human_male')
            bound = importer.equipment(template, descriptor['shared_template'], race)
            catalog.setdefault('equipment', {}).setdefault(race, {})[template] = bound
            if bound['status'] == 'ready' and bound['kind'] == 'skinned': descriptor = importer.owner_bound_preview(bound, descriptor)
        previous_shared = catalog['items'].get(template, {}).get('shared_template')
        if previous_shared != descriptor['shared_template'] and catalog['aliases'].get(previous_shared) == template:
            del catalog['aliases'][previous_shared]
        catalog['items'][template] = descriptor
        # Multiple server templates may intentionally share one original model.
        # Server lookup remains exact; shared-only lookup picks a stable entry.
        alias = descriptor['shared_template']
        catalog['aliases'][alias] = min(template, catalog['aliases'].get(alias, template))
        print(descriptor['status'], template, descriptor.get('triangles', 0), flush=True)
    if equipment_races:
        equipment = catalog.setdefault('equipment', {})
        for race_id in sorted(equipment_races):
            if not re.fullmatch(r'[a-z]+_(male|female)', race_id):
                raise ValueError('Invalid player equipment race: ' + race_id)
            variants = equipment.setdefault(race_id, {})
            for template in sorted(requested):
                if not template.startswith(('object/tangible/wearables/', 'object/weapon/')):
                    continue
                allowed = race_rules.get(template, [])
                if allowed and 'object/creature/player/'+race_id+'.iff' not in allowed: continue
                shared = pairs.get(template, canonical(template)[1])
                cached = variants.get(template, {})
                descriptor = cached if not args.refresh and importer.reusable_equipment(cached, shared, race_id) else importer.equipment(template, shared, race_id)
                variants[template] = descriptor
                previous = catalog['items'].get(template, {})
                preview_race = 'wookiee_male' if '/kashyyykian_' in template else 'human_male'
                if descriptor['status'] == 'ready' and descriptor['kind'] == 'skinned' and (previous.get('status') != 'ready' or (previous.get('owner_race') and race_id == preview_race)):
                    catalog['items'][template] = importer.owner_bound_preview(descriptor, previous)
                print('equipment', race_id, descriptor['status'], template, flush=True)
    catalog['provenance']['dependencies'].update(importer.character.dependencies)
    catalog['provenance']['tre_directory'] = str(args.tre_dir.resolve())
    catalog['policy'] = 'Original local SWG item appearances only; inventory ownership/equipment is supplied separately by Core3. Unsupported previews remain explicit. No colliders, icons or replacement models are synthesized.'
    catalog['failures'] = [{'template': t, **failure} for t, item in catalog['items'].items() for failure in item['failures']]
    catalog['equipment_failures'] = [{'race': race, 'template': template, **failure} for race, items in catalog.get('equipment', {}).items() for template, item in items.items() for failure in item['failures']]
    catalog['statistics'] = {'items': len(catalog['items']), 'ready': sum(i['status'] == 'ready' for i in catalog['items'].values()),
                             'unsupported': sum(i['status'] != 'ready' for i in catalog['items'].values()),
                             'unique_models': len({i['model'] for i in catalog['items'].values() if i['status'] == 'ready'}),
                             'source_hashes': len(catalog['provenance']['dependencies'])}
    catalog['statistics']['equipment_variants'] = sum(len(items) for items in catalog.get('equipment', {}).values())
    catalog['statistics']['equipment_failures'] = len(catalog['equipment_failures'])
    importer.character.write('catalog.json', catalog)
    print(json.dumps(catalog['statistics']), flush=True)


if __name__ == '__main__':
    main()
