#!/usr/bin/env python3
"""Preserve snapshot building terrain modifications and original interior footprints."""
import argparse, hashlib, json, struct
from pathlib import Path
from PIL import Image, ImageDraw
from swg_formats import TreSet, Iff, parse_iff, cstring
from terrain_formats import generator
from planet_config import PLANETS, path_for
ROOT = Path(__file__).resolve().parents[2]

def prepare(tre_directory, output, stage_path, planet="tatooine"):
    tre = TreSet(tre_directory)
    dependencies, cache, failures = {}, {}, []
    def read(name):
        raw = tre.read(name)
        dependencies[name] = {'archive': tre.entries[name][0].name, 'bytes': len(raw), 'sha256': hashlib.sha256(raw).hexdigest()}
        return raw
    def properties(name):
        if name in cache: return cache[name]
        root = parse_iff(read(name)); result = {}
        derived = next(root.walk('DERV'), None)
        if derived: result.update(properties(cstring(derived.first('XXXX').data)[0]))
        for node in root.walk('XXXX'):
            if b'\0' not in node.data: continue
            key, offset = cstring(node.data)
            if key in ('terrainModificationFileName', 'portalLayoutFilename'):
                value = node.data[offset:]
                if value[:1] == b'\x01': result[key] = cstring(value, 1)[0]
        cache[name] = result
        return result
    snapshot = parse_iff(read(f'snapshot/{planet}.ws'))
    names = snapshot.first('OTNL').data[4:].split(b'\0')
    placements, sources, buildings = [], {}, 0
    for node in snapshot.walk('NODE'):
        data = node.first('DATA').data
        oid, parent, tid, cell = struct.unpack_from('<4I', data)
        template = names[tid].decode()
        if parent or not template.startswith('object/building/'): continue
        buildings += 1
        try:
            name = properties(template).get('terrainModificationFileName', '')
            if not name: continue
            if name not in sources:
                raw = read(name); nodes = []; offset = 0
                while offset < len(raw):
                    length = struct.unpack_from('>I', raw, offset + 4)[0] + 8
                    nodes.append(parse_iff(raw[offset:offset+length])); offset += length
                sources[name] = generator(Iff('0000', b'', nodes))
            placements.append({'object_id': oid, 'template': template, 'source': name,
                               'position': list(struct.unpack_from('<3f', data, 32)),
                               'quaternion_wxyz': list(struct.unpack_from('<4f', data, 16))})
        except Exception as exc: failures.append({'template': template, 'error': str(exc)})
    output.mkdir(parents=True, exist_ok=True)
    triangles=[]; masks=[]
    if planet=='tatooine' and stage_path.exists():
        stage = json.loads(stage_path.read_text()); origin = stage['origin']; triangles = []
        for cell in stage['cells'].values():
            if cell['is_exterior']: continue
            vertices, indices = cell['floor_vertices'], cell['floor_indices']
            for offset in range(0, len(indices), 3):
                triangles.append([(origin[0]+vertices[i*3], origin[2]-vertices[i*3+2]) for i in indices[offset:offset+3]])
        points = [p for tri in triangles for p in tri]
        xmin, zmin = min(p[0] for p in points)-1, min(p[1] for p in points)-1
        xmax, zmax = max(p[0] for p in points)+1, max(p[1] for p in points)+1
        resolution = 2048
        image = Image.new('L', (resolution, resolution)); draw = ImageDraw.Draw(image)
        for tri in triangles:
            draw.polygon([((x-xmin)/(xmax-xmin)*(resolution-1), (z-zmin)/(zmax-zmin)*(resolution-1)) for x,z in tri], fill=255)
        output.mkdir(parents=True, exist_ok=True)
        image.save(output/'starport-interior-mask.png')
        masks=[{'path':'starport-interior-mask.png','world_rect':[xmin,zmin,xmax-xmin,zmax-zmin], 'source':'original non-exterior starport FLR triangles','triangles':len(triangles),'resolution':resolution,'stage_manifest_sha256':hashlib.sha256(stage_path.read_bytes()).hexdigest()}]
    report = {'schema_version': 1, 'snapshot_buildings_examined': buildings,
              'modification_sources': sources, 'modifications': placements,
              'interior_masks': masks,
              'planet':planet,
              'provenance': {'dependencies': dependencies}, 'failures': failures}
    (output/'context.json').write_text(json.dumps(report, separators=(',',':')))
    print(json.dumps({'buildings': buildings,'modifications':len(placements),'sources':list(sources),'interior_triangles':len(triangles),'failures':failures},indent=2))

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--planet', choices=PLANETS, default='tatooine')
    parser.add_argument('--tre-dir', type=Path, default=ROOT/'runtime/assets/active_tre')
    parser.add_argument('--out', type=Path, default=None)
    parser.add_argument('--stage', type=Path, default=ROOT/'runtime/assets/mos_eisley/scene.json')
    args = parser.parse_args(); prepare(args.tre_dir, args.out or path_for(args.planet,"terrain"), args.stage,args.planet)
