#!/usr/bin/env python3
"""Convert original JtL environments from the user's TREs, never substitute assets.

Output is private runtime data. Core3 owns NPC spawns, combat and event clocks;
this manifest supplies authored presentation and navigation references only.
"""
import argparse
import hashlib
import io
import json
import math
import re
import struct
import sys
from pathlib import Path
from PIL import Image
from character_formats import datatable, qmul
from static_assets import StaticAssets
from swg_formats import cstring, parse_iff
from stf import string_table
from prepare_stage import mirror, qmirror
from space_asteroids import field_instances

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT/'tools/combat'))
from tools.combat.prepare_assets import Assets as EffectAssets
SECTORS = ('corellia', 'dantooine', 'dathomir', 'endor', 'lok', 'naboo',
           'tatooine', 'yavin4', 'light1', 'heavy1')
NAMES = dict(corellia='Corellia', dantooine='Dantooine', dathomir='Dathomir',
             endor='Endor', lok='Lok', naboo='Naboo', tatooine='Tatooine',
             yavin4='Yavin IV', light1='Deep Space', heavy1='Kessel')
SCRIPTS = ROOT / 'vendor/Core3/MMOCoreORB/bin/scripts'
NUMBER = r'[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?'


def dump(path, value):
    path.write_text(json.dumps(value, separators=(',', ':'), allow_nan=False) + '\n')
    return hashlib.sha256(path.read_bytes()).hexdigest()


def floats(data, offset=0):
    assert (len(data)-offset) % 4 == 0
    return list(struct.unpack_from('<'+'f'*((len(data)-offset)//4), data, offset))


def local_source(path):
    return dict(path=str(path.relative_to(ROOT)), sha256=hashlib.sha256(path.read_bytes()).hexdigest())


def shared(path):
    p = Path(path)
    return str(p.parent / ('shared_'+p.name)) if not p.name.startswith('shared_') else path


class SectorAssets(EffectAssets):
    def original_parts(self, source):
        try:
            if source.endswith('.prt'):
                self.particle(source)
                return []
            return self.resolve(source)
        except (KeyError, ValueError, AssertionError) as error:
            self.failures.append(dict(resource=source, phase='sector_geometry', error=str(error)))
            return []

    def texture(self, source):
        data = self.read(source)
        path = 'textures/'+hashlib.sha256(data).hexdigest()[:20]+'.png'
        target = self.out/path; target.parent.mkdir(exist_ok=True)
        if not target.exists(): Image.open(io.BytesIO(data)).convert('RGBA').save(target)
        return dict(source=source, path=path)

    def shader_textures(self, source):
        root = parse_iff(self.read(source)); result = {}
        for node in root.walk('TXM '):
            name = cstring(node.first('NAME').data)[0].replace('\\', '/')
            name = name[name.index('texture/'):]
            tag = node.first('DATA').data[:4][::-1].decode('ascii')
            result[tag] = self.texture(name)
        if not result: raise ValueError('Shader has no texture bindings: '+source)
        return result

    def planet(self, path):
        root = parse_iff(self.read(path))
        if root.tag != 'PLNT' or root.children[0].tag != '0000':
            raise ValueError('Unsupported original planet: '+path)
        out = dict(source=path, subdivisions=list(struct.unpack('<2i', root.first('INIT').data)))
        for name, key in [('SURF', 'surface'), ('CLOD', 'clouds')]:
            node = next(root.walk(name), None)
            if not node: continue
            shader, offset = cstring(node.data, 4)
            values = floats(node.data, offset)
            out[key] = dict(rotation_degrees=struct.unpack_from('<f', node.data)[0],
                            shader=shader, textures=self.shader_textures(shader), radius=values[0], uv_scales=values[1:])
        node = next(root.walk('HALO'), None)
        if node:
            shader, offset = cstring(node.data)
            out['halo'] = dict(shader=shader, textures=self.shader_textures(shader), scale=floats(node.data, offset)[0])
        return out

    def environment(self, zone):
        path = 'terrain/'+zone+'.trn'; root = parse_iff(self.read(path))
        if root.tag != 'STAT': raise ValueError('Not a space terrain: '+path)
        out = dict(source=path, width=16384, planets=[], distant=[], celestials=[], lights=[])
        for form in root.children[0].children:
            raw = form.children[0].data if form.children else form.data
            if form.tag == 'CLEA': out['clear'] = floats(raw)
            elif form.tag == 'AMBI': out['ambient'] = floats(raw)
            elif form.tag == 'PARA':
                out['lights'].append(dict(dot3=bool(raw[0]), values=floats(raw, 1)))
            elif form.tag == 'FOG ': out['fog'] = floats(raw)
            elif form.tag == 'SIZE': out['width'] = floats(raw)[0]
            elif form.tag == 'SKYB':
                mask = cstring(raw, 1)[0]
                out['skybox'] = dict(mask=mask, cube=bool(raw[0]), faces={
                    face:self.texture('texture/'+mask+'_'+face+'.dds')
                    for face in ('front','back','left','right','top','bottom')})
            elif form.tag == 'STAR':
                ramp, offset = cstring(raw)
                out['stars'] = dict(ramp=self.texture(ramp), count=struct.unpack_from('<i', raw, offset)[0])
            elif form.tag == 'PLAN':
                appearance, offset = cstring(raw); values = floats(raw, offset)
                out['planets'].append(dict(position=mirror(values[:3]), angles=values[3:6],
                    halo_roll=values[6], halo_scale=values[7], **self.planet(appearance)))
            elif form.tag == 'DIST':
                appearance, offset = cstring(raw); values = floats(raw, offset)
                parts = self.original_parts(appearance)
                out['distant'].append(dict(source=appearance, position=mirror(values[:3]), angles=values[3:6], meshes=[p['mesh'] for p in parts], particle=self.particles.get(appearance, {})))
            elif form.tag == 'CELE':
                back, offset = cstring(raw); back_size = floats(raw[offset:offset+4])[0]
                front, offset = cstring(raw, offset+4); values = floats(raw, offset)
                out['celestials'].append(dict(back=self.shader_textures(back) if back else {}, back_size=back_size,
                    front=self.shader_textures(front) if front else {}, front_size=values[0], position=mirror(values[1:4])))
        return out

    def static_stage(self, instances, extra_meshes=()):
        keys = {i['mesh'] for i in instances} | set(extra_meshes)
        return dict(origin=[0,0,0], spawn=[0,0,0], cells={}, collisions={}, instances=instances,
                    meshes={key:json.loads((self.out/self.meshes[key]['path']).read_text()) for key in sorted(keys)})

    def place_static(self, template, position, quaternion=(1,0,0,0), ident=1):
        parts, _, _ = self.place(dict(id=ident, parent=0, template=shared(template), p=position, q=quaternion), [0,0,0])
        if not parts: raise ValueError('No original geometry: '+template)
        for part in parts:
            part.pop('collision_id', None); part.pop('collision_owner', None)
        return parts


def stations(assets, zone):
    source = (SCRIPTS/'managers/space/space_manager.lua').read_text()
    block = re.search(r'^'+zone+r'\s*=\s*\{(.*?)(?=^\w+\s*=|\Z)', source, re.M|re.S)[1]
    instances, markers = [], []
    for ident, match in enumerate(re.finditer(r'\{templateFile\s*=\s*"([^"]+)"([^}]+)\}', block), 100):
        name, fields = match.groups()
        values = {key:float(value) for key,value in re.findall(r'(\w+)\s*=\s*('+NUMBER+')', fields)}
        script = (SCRIPTS/'object/ship'/name).with_suffix('.lua')
        declaration = re.search(r'=\s*object_ship_shared_(\w+):new', script.read_text())
        if not declaration: raise ValueError('Station shared template missing: '+str(script))
        template = 'object/ship/shared_'+declaration[1]+'.iff'
        point = [values[k] for k in ('x','z','y')]
        instances.extend(assets.place_static(template, point, [values[k] for k in ('ow','ox','oy','oz')], ident))
        markers.append(dict(id=name+'_'+str(ident), name=name.replace('_',' ').title(), kind='station', position=point))
    return instances, markers


def landmarks(assets, zone):
    source = (SCRIPTS/'screenplays/space/spawning/space_objects.lua').read_text()
    pattern = r'\{\s*"'+zone+r'",\s*"([^"]+)"\s*,\s*('+NUMBER+r')\s*,\s*('+NUMBER+r')\s*,\s*('+NUMBER+r')\s*\}'
    instances, markers = [], []
    for ident, match in enumerate(re.finditer(pattern, source), 1000):
        template, *point = match.groups(); point = list(map(float, point))
        instances.extend(assets.place_static(template, point, ident=ident))
        markers.append(dict(id='landmark_'+str(ident), name=Path(template).stem.replace('_',' ').title(), kind='landmark', position=point))
    return instances, markers


def prepare(tre, out, allow_missing_original_media=False):
    out = Path(out); assets = SectorAssets(tre, out)
    names = string_table(assets.read('string/en/hyperspace_points_n.stf'))
    descriptions = string_table(assets.read('string/en/hyperspace_points_d.stf'))
    jumps = datatable(assets.read('datatables/space/hyperspace/hyperspace_locations.iff'))
    sectors = {}
    for suffix in SECTORS:
        zone = 'space_'+suffix; start = len(assets.failures)
        environment = assets.environment(zone)
        instances, markers = stations(assets, zone)
        scenery, points = landmarks(assets, zone); instances.extend(scenery); markers.extend(points)
        navigation = [dict(id=r['HYPERSPACE_POINT_NAME'], zone=r['SCENE'], name=names.get(r['HYPERSPACE_POINT_NAME'],r['HYPERSPACE_POINT_NAME']),
            description=descriptions.get(r['HYPERSPACE_POINT_NAME'], ''), position=[r[k] for k in ('X','Y','Z')],
            required_command=r.get('REQUIRED_COMMAND','')) for r in jumps if r['SCENE']==zone]
        tables = {}
        for kind in ('asteroidfield','nebula'):
            path = 'datatables/space/'+kind+'/'+zone+'.iff'
            tables[kind] = datatable(assets.read(path)) if path in assets.t.entries else []
        for field in tables['asteroidfield']:
            for key in ('FieldStyleTable','RadialStyleTable'):
                source = field[key]
                # The shipped Dantooine table misspells this existing style.
                # Preserve the authored reference and record the exact repair.
                if source == 'datatables/space/asteroidfield/fieldstyle/astroid_basic_obsidian.iff':
                    source = 'datatables/space/asteroidfield/fieldstyle/asteroid_basic_obsidian.iff'
                    field[key+'_resolved'] = source
                field[key+'_rows'] = datatable(assets.read(source)) if source else []
                for style in field[key+'_rows']:
                    source = style.get('SharedTemplate',style.get('Appearance',''))
                    style['meshes'] = [p['mesh'] for p in assets.original_parts(source)]
        for field in tables['asteroidfield']:
            field['instances'] = field_instances(assets, field)
        extra = [mesh for d in environment['distant'] for mesh in d['meshes']]
        extra += [mesh for f in tables['asteroidfield'] for k in ('FieldStyleTable','RadialStyleTable') for r in f[k+'_rows'] for mesh in r['meshes']]
        stage = assets.static_stage(instances, extra)
        stage.update(schema_version=2, source_zone=zone, name=NAMES[suffix], environment=environment,
                     navigation=navigation, markers=markers, **tables)
        source_files = [SCRIPTS/'managers/space/space_manager.lua', SCRIPTS/'screenplays/space/spawning/space_objects.lua',
                        SCRIPTS/('screenplays/space/spawning/'+zone+'_spawner.lua'), SCRIPTS/'screenplays/space/spawning/space_spawner.lua']
        stage['native_sources'] = [local_source(p) for p in source_files]
        stage['provenance'] = assets.dependencies.copy(); stage['conversion_failures'] = list({json.dumps(row,sort_keys=True):row for row in assets.failures[start:]}.values())
        descriptor = zone+'.json'; digest = dump(out/descriptor, stage)
        sectors[zone] = dict(descriptor=descriptor, sha256=digest, name=NAMES[suffix], navigation=navigation,
                             planets=len(environment['planets']), landmarks=len(markers), asteroid_fields=len(tables['asteroidfield']), nebulae=len(tables['nebula']))
        print(json.dumps(dict(zone=zone, instances=len(instances), meshes=len(stage['meshes']), failures=stage['conversion_failures'])), flush=True)
    path = out/'catalog.json'
    catalog = json.loads(path.read_text()) if path.exists() else dict(schema_version=1, templates={})
    catalog['sectors'] = sectors
    catalog['sector_provenance'] = assets.dependencies
    catalog['sector_conversion_failures'] = list({json.dumps(row,sort_keys=True):row for row in assets.failures}.values())
    catalog['sector_visual_limitations'] = ['Nebula lightning and proximity-driven radial asteroid debris are not yet rendered', 'Asteroid rotation dynamics and original planet detail shader stages remain incomplete', 'Stars retain source seeded directions and colours with a fixed angular cubemap footprint instead of two-pixel points', 'Nebula generation uses a deterministic client RNG rather than the source global random stream']
    dump(path, catalog)
    known = {'object/static/space/asteroid/shared_asteroid_molten_mammoth_0%d.iff'%i for i in (1,2)}
    if assets.failures and (not allow_missing_original_media or any(row.get('resource') not in known for row in assets.failures)):
        raise RuntimeError('Sector conversion has recorded failures; inspect the catalog. Only the two documented absent original asteroid templates may be explicitly accepted for a limited test build.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tre-dir', type=Path, default=ROOT/'runtime/asset_sources/active_tre')
    parser.add_argument('--out', type=Path, default=ROOT/'runtime/assets/jtl')
    parser.add_argument('--allow-missing-original-media', action='store_true', help='Accept only the documented absent Dathomir asteroid templates; preserve all failures in catalogs')
    args = parser.parse_args(); prepare(args.tre_dir, args.out, args.allow_missing_original_media)
