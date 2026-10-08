#!/usr/bin/env python3
"""Read-only catalog audit: authored walkable FLR versus coarse CMSH body clearance.

Candidates are geometric intersections, not a claim that every source overlap
blocks an intended route. Actual capsule motion and cell membership still need
native tests. Original data is neither changed nor copied into tracked files.
"""
import argparse
import collections
import json
from pathlib import Path
import numpy as np
from audit_portal_closures import transform, meshes, audit


def leaves(node):
    kind = node.get('type', 'missing')
    if kind == 'transform':
        yield from leaves(node.get('child', {}))
    elif kind in ('component', 'composite', 'detail'):
        children = node.get('children', [])
        for child in children[1 if kind == 'detail' and len(children) > 1 else 0:]:
            yield from leaves(child)
    else:
        yield kind


_support_cache = (None, None)


def support_at(floor, point, reference_height, tolerance=.35):
    global _support_cache
    if not floor:
        return []
    if _support_cache[0] is not floor:
        vertices = np.array([p for _, p in floor])
        a, u, v = vertices[:, 0], vertices[:, 1] - vertices[:, 0], vertices[:, 2] - vertices[:, 0]
        determinant = u[:, 0] * v[:, 2] - v[:, 0] * u[:, 2]
        valid = np.abs(determinant) >= 1e-10
        determinant = np.where(valid, determinant, 1.)
        _support_cache = (floor, (a, u, v, determinant, valid))
    a, u, v, determinant, valid = _support_cache[1]
    delta = point - a
    b = (delta[:, 0] * v[:, 2] - v[:, 0] * delta[:, 2]) / determinant
    c = (u[:, 0] * delta[:, 2] - delta[:, 0] * u[:, 2]) / determinant
    height = a[:, 1] + b * u[:, 1] + c * v[:, 1]
    match = valid & (b >= -1e-6) & (c >= -1e-6) & (b + c <= 1.000001) & (np.abs(height - reference_height) <= tolerance)
    return [floor[i][0]['id'] for i in np.flatnonzero(match)]


def closed_edge_crossings(floor):
    candidates = []
    for source, points in floor:
        for index, flag in enumerate(source.get('edge_flags', [])):
            if flag != 0 or source.get('portal_ids', [-1, -1, -1])[index] >= 0:
                continue
            a, b = points[index], points[(index + 1) % 3]
            edge = b - a
            normal = np.array([-edge[2], 0., edge[0]])
            if np.linalg.norm(normal) < 1e-8:
                continue
            normal /= np.linalg.norm(normal)
            if normal @ (points[(index + 2) % 3] - a) < 0:
                normal = -normal
            midpoint = (a + b) * .5
            inside = support_at(floor, midpoint + normal * .3, midpoint[1])
            outside = support_at(floor, midpoint - normal * .3, midpoint[1])
            if inside and outside:
                candidates.append(dict(floor_triangle=source['id'], edge=index, local_midpoint=midpoint.tolist(), supported_inside=inside, supported_outside=outside))
    return candidates


def portal_corridors(floor, portals, inverse, mesh_triangles):
    """Finite normal-line reach through each portal's connected solid FLR graph."""
    by_id = {source['id']: (source, vertices) for source, vertices in floor}
    results = []
    for portal_index, portal in enumerate(portals):
        if not portal.get('passable') or portal.get('source_disabled'):
            continue
        local_index = portal.get('floor_portal_index', portal_index)
        roots = [source['id'] for source, _ in floor if local_index in source.get('portal_ids', [])]
        if not roots:
            continue
        connected = set(roots); pending = list(roots)
        while pending:
            source, _ = by_id[pending.pop()]
            for edge, neighbor in enumerate(source.get('neighbors', [])):
                if neighbor not in by_id or neighbor in connected or source.get('edge_flags', [0]*3)[edge] != 1:
                    continue
                connected.add(neighbor); pending.append(neighbor)
        vertices = np.array(portal['vertices']).reshape(-1, 3)
        vertices = vertices @ inverse[:3, :3].T + inverse[:3, 3]
        center = vertices.mean(axis=0)
        normal = np.cross(vertices[1] - vertices[0], vertices[2] - vertices[0])
        normal /= np.linalg.norm(normal)
        if abs(normal[1]) > .25:
            continue
        intervals = []
        for identifier in connected:
            _, triangle = by_id[identifier]
            lo, hi = -1e6, 1e6
            centroid = triangle.mean(axis=0)
            for edge in range(3):
                a, b = triangle[edge], triangle[(edge + 1) % 3]
                side = np.array([-(b - a)[2], 0., (b - a)[0]])
                if side @ (centroid - a) < 0:
                    side = -side
                distance, speed = side @ (center - a), side @ normal
                if abs(speed) < 1e-10:
                    if distance < -1e-7:
                        hi = -1e6
                        break
                elif speed > 0:
                    lo = max(lo, -distance / speed)
                else:
                    hi = min(hi, -distance / speed)
            if hi >= lo:
                intervals.append([float(lo), float(hi), identifier])
        merged = []
        for lo, hi, identifier in sorted(intervals):
            if merged and lo <= merged[-1][1] + .03:
                merged[-1][1] = max(merged[-1][1], hi)
            else:
                merged.append([lo, hi])
        near = [span for span in merged if span[0] <= .3 and span[1] >= -.3]
        source_audit = audit(mesh_triangles, vertices)
        results.append(dict(portal_id=portal['id'], floor_portal_index=local_index, root_triangles=roots,
                            connected_triangles=sorted(connected), local_center=center.tolist(), normal=normal.tolist(),
                            connected_normal_intervals=intervals, contiguous_portal_span=near,
                            nearest_center_plane=source_audit.get('nearest_center_plane'),
                            original_expansion_bound_m=source_audit.get('expansion_bound_m')))
    return results


def terrain_handoffs(floor, all_sources):
    by_id = {t['id']: t for t in all_sources}
    result = []
    for source, vertices in floor:
        for edge, flag in enumerate(source.get('edge_flags', [])):
            neighbor = source.get('neighbors', [-1] * 3)[edge]
            adjacent = by_id.get(neighbor)
            if flag != 1 or source.get('portal_ids', [-1] * 3)[edge] >= 0:
                continue
            if adjacent is not None and not adjacent.get('fallthrough'):
                continue
            a, b, third = vertices[edge], vertices[(edge + 1) % 3], vertices[(edge + 2) % 3]
            midpoint = (a + b) * .5
            tangent = b - a
            normal = np.array([-tangent[2], 0., tangent[0]])
            width = np.linalg.norm(normal)
            if width < 1e-8:
                continue
            normal /= width
            if normal @ (third - midpoint) < 0:
                normal = -normal
            slope_normal = np.cross(vertices[1] - vertices[0], vertices[2] - vertices[0])
            if slope_normal[1] < 0:
                slope_normal = -slope_normal
            if slope_normal[1] < .5 * np.linalg.norm(slope_normal):
                continue
            rise = float(third[1] - midpoint[1])
            slope = -float(slope_normal @ normal) / float(slope_normal[1])
            # At this position a 22cm capsule already overlaps the original
            # ramp footprint while its center still samples terrain only.
            capsule_center = midpoint - normal * .11
            result.append(dict(floor_triangle=source['id'], edge=edge, edge_flag=flag, neighbor=neighbor,
                               neighbor_fallthrough=bool(adjacent and adjacent.get('fallthrough')),
                               local_edge=[a.tolist(), b.tolist()], width_m=float(width),
                               inward_direction=normal.tolist(), inward_slope=slope,
                               terrain_to_ramp_toe=slope > .01,
                               local_capsule_overlap_center=capsule_center.tolist(), capsule_radius_m=.22))
    return result


def hits(floor, triangles):
    """Intersect CMSH with planes 0.35/0.9/1.5m above each real FLR triangle."""
    if not len(triangles):
        return []
    bounds_lo, bounds_hi = triangles.min(axis=1), triangles.max(axis=1)
    normals = np.cross(triangles[:, 1] - triangles[:, 0], triangles[:, 2] - triangles[:, 0])
    norms = np.linalg.norm(normals, axis=1)
    vertical = np.abs(normals[:, 1]) < .7 * norms
    result = []
    for source, f in floor:
        n = np.cross(f[1] - f[0], f[2] - f[0])
        if n[1] < 0:
            n = -n
        if n[1] < .5 * np.linalg.norm(n):
            continue
        low, high = f.min(axis=0), f.max(axis=0)
        broad = vertical & (bounds_hi[:, 0] >= low[0]) & (bounds_lo[:, 0] <= high[0]) & (bounds_hi[:, 2] >= low[2]) & (bounds_lo[:, 2] <= high[2]) & (bounds_hi[:, 1] >= low[1] + .35) & (bounds_lo[:, 1] <= high[1] + 1.5)
        for index in np.flatnonzero(broad):
            wall = triangles[index]
            for height in (.35, .9, 1.5):
                d = (wall - f[0]) @ n / n[1] - height
                points = []
                for j in range(3):
                    k = (j + 1) % 3
                    if d[j] * d[k] < 0:
                        points.append(wall[j] + (wall[k] - wall[j]) * d[j] / (d[j] - d[k]))
                if len(points) != 2:
                    continue
                a, b = points
                # Clip the line segment against the finite FLR footprint. A
                # positive inset rejects ordinary wall/floor boundary contact.
                lo_t, hi_t = 0., 1.
                center = f.mean(axis=0)
                for j in range(3):
                    edge = f[(j + 1) % 3] - f[j]
                    side = np.array([-edge[2], 0., edge[0]])
                    side /= np.linalg.norm(side)
                    if side @ (center - f[j]) < 0:
                        side = -side
                    da, db = side @ (a - f[j]) - .03, side @ (b - f[j]) - .03
                    if da < 0 and db < 0:
                        hi_t = -1.; break
                    if da < 0:
                        lo_t = max(lo_t, da / (da - db))
                    elif db < 0:
                        hi_t = min(hi_t, da / (da - db))
                if hi_t <= lo_t:
                    continue
                p, q = a + (b - a) * lo_t, a + (b - a) * hi_t
                length = np.linalg.norm((q - p)[[0, 2]])
                if length < .15:
                    continue
                midpoint = (p + q) * .5
                wall_normal = normals[index].copy(); wall_normal[1] = 0
                wall_normal /= np.linalg.norm(wall_normal)
                floor_height = midpoint[1] - height
                support_a = support_at(floor, midpoint + wall_normal * .3, floor_height)
                support_b = support_at(floor, midpoint - wall_normal * .3, floor_height)
                result.append(dict(supported_both_sides=bool(support_a and support_b), support_sides=[support_a, support_b], floor_triangle=source['id'], mesh_triangle=int(index), body_height_m=height, overlap_length_m=float(length), local_segment=[p.tolist(), q.tolist()], floor_normal=(n / np.linalg.norm(n)).tolist()))
                break
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--assets', type=Path, default=Path('runtime/assets'))
    parser.add_argument('--output', type=Path, default=Path('runtime/evidence/floor-transition-catalog-audit.json'))
    args = parser.parse_args()
    worlds = [args.assets / 'tatooine_world/world.json', *sorted((args.assets / 'planets').glob('*/world/world.json'))]
    prototypes = {}; planet_counts = {}; placements = set()
    for path in worlds:
        world = json.loads(path.read_text()); definitions = world['collisions']; counts = collections.Counter()
        for chunkpath in sorted((path.parent / 'chunks').glob('*.json')):
            chunk = json.loads(chunkpath.read_text())
            for entry in chunk['instances']:
                cell_id = entry.get('cell_id', '')
                cell = chunk.get('cells', {}).get(cell_id)
                if not cell or not entry.get('collision_owner', True) or entry.get('collision_id') != cell.get('collision_id'):
                    continue
                placement = (str(path), cell_id)
                if placement in placements:
                    continue
                placements.add(placement); counts['cell_placements'] += 1
                collision = entry['collision_id']; definition = definitions[collision].get('extent', {})
                if collision not in prototypes:
                    inverse = np.linalg.inv(transform(entry.get('position', [0, 0, 0]), entry.get('quaternion', [0, 0, 0, 1]), entry.get('scale', [1, 1, 1])))
                    vertices = np.array(cell.get('floor_vertices', [])).reshape(-1, 3)
                    vertices = vertices @ inverse[:3, :3].T + inverse[:3, 3]
                    floor = [(t, vertices[t['indices']]) for t in cell.get('floor_triangles', []) if not t.get('fallthrough')]
                    arrays = list(meshes(definition)); triangles = np.concatenate(arrays) if arrays else np.empty((0, 3, 3))
                    candidates = hits(floor, triangles)
                    closed = sum(t.get('edge_flags', [1, 1, 1])[i] == 0 and t.get('portal_ids', [-1, -1, -1])[i] < 0 for t, _ in floor for i in range(3))
                    prototypes[collision] = dict(collision=collision, exterior=cell.get('is_exterior', False), extent_types=dict(collections.Counter(leaves(definition))), floor_triangles=len(floor), closed_edges=closed, portal_floor_corridors=portal_corridors(floor, cell.get('portals', []), inverse, triangles) if cell.get('is_exterior') else [], terrain_handoff_edges=terrain_handoffs(floor, cell.get('floor_triangles', [])) if cell.get('is_exterior') else [], closed_edge_support_candidates=closed_edge_crossings(floor), sloped_floor_triangles=sum(bool(.01 < np.ptp(f[:, 1])) for _, f in floor), cms_mesh_triangles=len(triangles), clearance_candidates=candidates, placements=[])
                prototypes[collision]['placements'].append(dict(planet=world.get('planet', path.parent.parent.name), cell=cell_id, chunk=str(chunkpath), position=entry['position']))
        planet_counts[world.get('planet', path.parent.parent.name)] = dict(counts)
    rows = list(prototypes.values())
    report = dict(read_only=True, source_worlds=[str(p) for p in worlds], planets=planet_counts, unique_source_cells=len(rows), cell_placements=len(placements), candidate_source_cells=sum(bool(r['clearance_candidates']) for r in rows), candidate_intersections=sum(len(r['clearance_candidates']) for r in rows), candidate_placements=sum(len(r['placements']) for r in rows if r['clearance_candidates']), terrain_handoff_edges=sum(len(r['terrain_handoff_edges']) for r in rows), terrain_ramp_toes=sum(sum(h['terrain_to_ramp_toe'] for h in r['terrain_handoff_edges']) for r in rows), terrain_ramp_toe_placements=sum(len(r['placements']) * sum(h['terrain_to_ramp_toe'] for h in r['terrain_handoff_edges']) for r in rows), two_sided_clearance_candidates=sum(sum(h['supported_both_sides'] for h in r['clearance_candidates']) for r in rows), closed_edge_support_candidates=sum(len(r['closed_edge_support_candidates']) for r in rows), limitation='Candidates require native traversal confirmation. Tests must preserve legitimate rails, walls, floor edges, height/storey separation and portal ownership. CMSH test examines sampled body heights only and does not cover primitives, terrain or runtime FLR edge constraints.', cells=rows)
    args.output.parent.mkdir(parents=True, exist_ok=True); args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({k: v for k, v in report.items() if k != 'cells'}, indent=2))


if __name__ == '__main__':
    main()
