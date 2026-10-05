"""Original INLY interior layouts: named-cell decorations and ambient emitters.

Transforms are rigid SWG row-major 3x4 matrices local to the building. Synthetic
negative IDs identify local render placements only, never Core3 game objects.
"""
import hashlib
import math
import struct
from swg_formats import parse_iff, cstring
from character_formats import qmul
from prepare_stage import qrot


def template_properties(read, path, cache=None, trail=()):
    cache = cache if cache is not None else {}
    if path in cache:
        return cache[path]
    if path in trail:
        raise ValueError('Cyclic template ' + path)
    root = parse_iff(read(path))
    inherited = next(root.walk('DERV'), None)
    result = dict(template_properties(read, cstring(inherited.first('XXXX').data)[0], cache, trail + (path,))) if inherited else {}
    for node in root.walk('XXXX'):
        if b'\0' not in node.data:
            continue
        key, offset = cstring(node.data)
        if node.data[offset:offset + 1] == b'\1':
            try:
                result[key] = cstring(node.data, offset + 1)[0]
            except (ValueError, UnicodeDecodeError):
                pass
    cache[path] = result
    return result


def matrix_quaternion(matrix):
    """SWG wxyz quaternion from a verified rigid rotation (no scale discarded)."""
    m = [[matrix[row * 4 + col] for col in range(3)] for row in range(3)]
    for a in range(3):
        for b in range(3):
            if abs(sum(m[a][i] * m[b][i] for i in range(3)) - (a == b)) > 0.003:
                raise ValueError('Non-rigid interior layout transform')
    determinant = sum(m[0][i] * (m[1][(i + 1) % 3] * m[2][(i + 2) % 3] - m[1][(i + 2) % 3] * m[2][(i + 1) % 3]) for i in range(3))
    if determinant < 0.99:
        raise ValueError('Reflected interior layout transform')
    trace = sum(m[i][i] for i in range(3))
    if trace > 0:
        s = math.sqrt(trace + 1.0) * 2
        q = [s / 4, (m[2][1] - m[1][2]) / s, (m[0][2] - m[2][0]) / s, (m[1][0] - m[0][1]) / s]
    else:
        i = max(range(3), key=lambda n: m[n][n]); j = (i + 1) % 3; k = (i + 2) % 3
        s = math.sqrt(1 + m[i][i] - m[j][j] - m[k][k]) * 2
        q = [0.0] * 4
        q[0] = (m[k][j] - m[j][k]) / s
        q[i + 1] = s / 4
        q[j + 1] = (m[j][i] + m[i][j]) / s
        q[k + 1] = (m[k][i] + m[i][k]) / s
    length = math.sqrt(sum(value * value for value in q))
    return [value / length for value in q]


def layout_records(read, path):
    root = parse_iff(read(path))
    if root.tag != 'INLY' or root.children[0].tag != '0000':
        raise ValueError('Unsupported interior layout ' + path)
    records = []
    for index, node in enumerate(root.walk('NODE')):
        template, offset = cstring(node.data)
        cell, offset = cstring(node.data, offset)
        if len(node.data) - offset != 48:
            raise ValueError('Invalid interior layout transform ' + path)
        matrix = struct.unpack_from('<12f', node.data, offset)
        records.append({'template': template, 'cell_name': cell, 'p': [matrix[3], matrix[7], matrix[11]], 'q': matrix_quaternion(matrix), 'source_layout': path, 'source_layout_index': index, 'source_layout_transform': list(matrix)})
    return records


def expand_layouts(importer, nodes):
    """Appendable world-space nodes; same schema/coordinate transform as snapshot."""
    result = []; properties = {}; layouts = {}; cells = {}
    for node in nodes:
        if node['template'] == 'object/cell/shared_cell.iff':
            cells[(node['parent'], node['cell'])] = node['id']
    for building in nodes:
        if not building['template'].startswith('object/building/'):
            continue
        try:
            props = template_properties(importer.read, building['template'], properties)
            layout = props.get('interiorLayoutFileName', '')
            if not layout:
                continue
            pob = props.get('portalLayoutFilename', '')
            if not pob:
                raise ValueError('Interior layout without POB')
            if layout not in layouts:
                layouts[layout] = layout_records(importer.read, layout)
            names = {}
            for index, cell in enumerate(parse_iff(importer.read(pob)).walk('CELL')):
                names[cstring(cell.first('DATA').data, 5)[0]] = index
            for record in layouts[layout]:
                if record['cell_name'] not in names:
                    raise ValueError('Unknown layout cell ' + record['cell_name'] + ' in ' + pob)
                cell_index = names[record['cell_name']]
                key = f"{building['id']}:{layout}:{record['source_layout_index']}"
                item = dict(record)
                item.update(id=-int(hashlib.sha256(key.encode()).hexdigest()[:13], 16) - 1,
                            parent=cells.get((building['id'], cell_index), building['id']), cell=cell_index,
                            cell_id=f"{building['id']}:{cell_index}", building_object_id=building['id'],
                            source_cell_object_id=cells.get((building['id'], cell_index), 0),
                            p=[a + b for a, b in zip(qrot(building['q'], record['p']), building['p'])],
                            q=qmul(building['q'], record['q']))
                result.append(item)
        except Exception as error:
            importer.failures.append({'resource': building['template'], 'object_id': building['id'], 'phase': 'interior_layout', 'error': str(error)})
    return result
