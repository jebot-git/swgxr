"""Original cockpit camera anchors and bounded, audited control components."""
import copy
import base64
import hashlib
import json
import struct
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'vehicles'))
from yoke_geometry import source_components
from swg_formats import parse_iff, cstring


def camera_anchor(assets, appearance, offset):
    """SWG CockpitCamera::createFrame finds camera, then applies CPIT 1OFF."""
    path = appearance
    for _ in range(8):
        source = parse_iff(assets.read(path))
        for hp in source.walk('HPNT'):
            if len(hp.data) > 48 and cstring(hp.data, 48)[0] == 'camera':
                transform = struct.unpack('<12f', hp.data[:48])
                point = [transform[r*4+3] + sum(transform[r*4+c]*offset[c] for c in range(3)) for r in range(3)]
                return [point[0], point[1], -point[2]], path
        if source.tag != 'APT ': break
        path = cstring(source.first('NAME').data)[0]
    raise ValueError('Original cockpit camera hardpoint missing: '+appearance)


def authored_stick(assets, out, descriptor, family):
    """Convert bundled original artwork through the normal native SWG reader."""
    recipe = json.loads(Path(__file__).with_name('authored_stick.json').read_text())
    profile = recipe['profiles'][family]
    files = {path: base64.b64decode(data) for path, data in recipe['files'].items()}
    original_read = assets.read
    def read(path):
        path = path.lower().replace('\\', '/')
        if path not in files:
            return original_read(path)
        data = files[path]
        assets.dependencies[path] = dict(archive='SWGXR original authored controls',
            sha256=hashlib.sha256(data).hexdigest(), bytes=len(data))
        return data
    before = len(assets.failures)
    assets.read = read
    try:
        parts = assets.resolve(profile['appearance'])
    finally:
        assets.read = original_read
    if not parts or len(assets.failures) != before:
        raise ValueError('Authored flight stick conversion failed: '+repr(assets.failures[before:]))
    meshes = {p['mesh']:json.loads((Path(out)/assets.meshes[p['mesh']]['path']).read_text()) for p in parts}
    offset = profile['offset']
    for mesh in meshes.values():
        for surface in mesh['surfaces']:
            surface['vertices'] = [v+offset[i%3] for i,v in enumerate(surface['vertices'])]
            if len(surface.get('colors', [])) != len(surface['vertices'])//3*4:
                raise ValueError('Flight stick vertex bake missing')
    stage = dict(schema_version=1, origin=[0,0,0], spawn=[0,0,0], meshes=meshes,
        instances=[dict(mesh=p['mesh'],position=[0,0,0],quaternion=[0,0,0,1]) for p in parts],
        cells={}, collisions={}, conversion_failures=[], provenance=assets.dependencies.copy())
    target = descriptor.replace('_cockpit.json', '_controls.json')
    path = Path(out)/target
    path.write_text(json.dumps(stage,separators=(',',':')))
    point = lambda p: [v+o for v,o in zip(p,offset)]
    return dict(descriptor=target,sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
        pivot=point([0,.075,0]),grips=[point([0,.66,.015])]*2,style='stick',borrowed=False,
        component_triangle_counts=[724],source='SWGXR original central stick; '+family+' vertex lighting',
        native_appearance=profile['appearance'])


def prepare_controls(out, descriptor, family, assets=None):
    """Move complete source components, retaining fixed columns and dashboards.

    Z95 and Xwing use the approved original central stick and individual bakes.
    """
    out = Path(out)
    if family in ('z95', 'xwing'):
        if assets is None:
            raise ValueError('Native asset reader is required for authored controls')
        return authored_stick(assets, out, descriptor, family)
    stage = json.loads((out/descriptor).read_text())
    borrowed = family == 'z95'
    original = json.loads((out/'fighter_tiefighter_cockpit.json').read_text()) if borrowed else stage
    if family not in ('tie', 'hutt', 'z95'): return {}
    chosen = copy.deepcopy(original)
    counts = []
    for key, model in original['meshes'].items():
        keep_surfaces = []
        for surface in model['surfaces']:
            selected = []
            for group in source_components(surface):
                lo, hi = group['bounds_min'], group['bounds_max']
                if borrowed:
                    keep = lo[0] > .179 and hi[0] < .23 and lo[1] > -.21 and hi[1] < .03 and lo[2] > -.44 and hi[2] < -.31
                elif family == 'hutt':
                    keep = len(group['triangles']) == 231 and lo[1] > .49 and hi[1] < .71 and lo[2] > -3.48 and hi[2] < -2.94
                else:
                    # Only the handles and their arms move. The central screen,
                    # buttons and housing belong to the stationary column.
                    keep = (lo[0] > .10 or hi[0] < -.10) and lo[0] > -.24 and hi[0] < .24 and lo[1] > -.22 and hi[1] < .03 and lo[2] > -.64 and hi[2] < -.31
                if keep:
                    counts.append(len(group['triangles']));selected.extend(group['triangles'])
            selected = set(selected)
            indices = surface['indices']
            if selected:
                part = copy.deepcopy(surface)
                part['indices'] = [indices[i] for i in range(len(indices)) if i//3 in selected]
                keep_surfaces.append(part)
            if not borrowed:
                surface['indices'] = [indices[i] for i in range(len(indices)) if i//3 not in selected]
        chosen['meshes'][key]['surfaces'] = keep_surfaces
    expected = [231,231] if family=='hutt' else [2,8,22,28,40,48,94,96]*2
    if borrowed:expected=[2,8,22,28,40,48,94]
    # Exact topology is part of the audit. Never silently cut a changed model.
    if sorted(counts) != sorted(expected):
        raise ValueError(f'Cockpit control topology changed ({family}): {sorted(counts)}')
    pivot = [0,.60,-3.25] if family=='hutt' else [0,-.10,-.40]
    grips = [[-.29,.56,-3.04],[.29,.56,-3.04]] if family=='hutt' else [[-.203,-.06,-.35],[.203,-.06,-.35]]
    if borrowed:
        shift = [-.203, .86, -1.68]
        for model in chosen['meshes'].values():
            for surface in model['surfaces']:
                surface['vertices'] = [v+shift[i%3] for i,v in enumerate(surface['vertices'])]
        pivot=[0,.65,-2.03]
        grips=[[0,.80,-2.03],[0,.80,-2.03]]
    else:
        (out/descriptor).write_text(json.dumps(stage,separators=(',',':')))
    target=descriptor.replace('_cockpit.json','_controls.json')
    chosen['collisions']={}
    (out/target).write_text(json.dumps(chosen,separators=(',',':')))
    return dict(descriptor=target, sha256=hashlib.sha256((out/target).read_bytes()).hexdigest(),
                pivot=pivot, grips=grips, component_triangle_counts=sorted(counts),
                style='stick' if borrowed else 'yoke',
                source='Original upright TIE grip adapted as the Z95 central stick' if borrowed else 'Complete original cockpit handle components',
                borrowed=borrowed)
