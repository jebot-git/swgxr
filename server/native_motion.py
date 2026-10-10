"""Read the native client's independent movement stream, fenced by RPG visibility.

This adds presentation goals only. It never refreshes native session/RPG age or
changes a target's health, ownership, visibility membership or hit result.
"""
import json
import math
import time


def newer_or_equal(a, b):
    return ((a - b) & 0xffffffff) < 0x80000000


def project(stream, world, character_id, now=None):
    try:
        return _project(stream, world, character_id, now)
    except (ValueError, TypeError, KeyError, OverflowError):
        # Optional presentation data cannot break an otherwise valid RPG sync.
        return {}


def _project(stream, world, character_id, now=None):
    now = time.time() if now is None else now
    if (not isinstance(stream, dict) or stream.get('source_kind') != 'core3_motion_v1'
            or stream.get('character_id') != character_id or stream.get('zone') != world.get('zone')):
        return {}
    if type(stream.get('epoch')) is not int or not 0 <= stream['epoch'] <= 2**53:
        return {}
    elapsed = (now - float(stream.get('written_at', 0))) * 1000
    if not math.isfinite(elapsed) or not -100 <= elapsed <= 500:
        return {}
    visible = {r['id']: r for r in world.get('actors', [])}
    result = {'source_kind': 'core3_motion_v1', 'epoch': stream['epoch'], 'actors': []}
    rows = stream.get('actors', [])
    if not isinstance(rows, list) or len(rows) > 512:
        return {}
    for row in rows:
        if not isinstance(row, dict) or type(row.get('sequence')) is not int or not 0 <= row['sequence'] <= 2**53:
            continue
        baseline = visible.get(row.get('id'))
        if not baseline or baseline.get('dead') or baseline.get('incapacitated'):
            continue
        # Missing baseline counter means an older server: retain snapshot fallback.
        if 'movement_counter' not in baseline or row.get('cell_id') != baseline.get('cell_id', '0'):
            continue
        counter = row.get('movement_counter')
        if type(counter) is not int or not 0 <= counter <= 0xffffffff or not newer_or_equal(counter, baseline['movement_counter']):
            continue
        age = float(row.get('age_ms', math.inf)) + max(0, elapsed)
        p = row.get('position')
        if not math.isfinite(age) or not 0 <= age <= 2000 or not isinstance(p, list) or len(p) != 3 or any(type(v) not in (int, float) or not math.isfinite(v) or abs(v) > 20000 for v in p):
            continue
        heading, speed = row.get('heading_radians'), row.get('speed')
        if any(type(v) not in (int, float) or not math.isfinite(v) for v in (heading, speed)) or not 0 <= speed <= 127:
            continue
        if row['cell_id'] != '0':
            # Core3's ground-cell transform is a yaw rotation around its root.
            local = baseline.get('local_position')
            angle = baseline.get('cell_heading_radians')
            if local is None or angle is None:
                continue
            dx, dy, dz = (p[i] - local[i] for i in range(3))
            c, s = math.cos(angle), math.sin(angle)
            p = [baseline['position'][0] + c*dx + s*dz,
                 baseline['position'][1] + dy,
                 baseline['position'][2] - s*dx + c*dz]
            heading += angle
        result['actors'].append({'id': row['id'], 'cell_id': row['cell_id'],
            'position': p, 'heading_radians': heading, 'movement_speed': speed,
            'movement_counter': counter, 'sequence': row['sequence'], 'age_ms': age})
    # Native CombatAction events are short-lived and visibility fenced, with a
    # monotonically increasing ID for client deduplication. Never infer attacks
    # from in_combat or fabricate a fire cadence from snapshot timing.
    events = stream.get('events', [])
    if isinstance(events, list) and len(events) <= 128:
        result['events'] = []
        for row in events:
            if not isinstance(row, dict): continue
            baseline = visible.get(row.get('id'))
            age = float(row.get('age_ms', math.inf)) + max(0, elapsed)
            if (not baseline or baseline.get('dead') or baseline.get('incapacitated')
                    or row.get('event') != 'attack' or type(row.get('sequence')) is not int
                    or not 0 <= row['sequence'] <= 2**53 or not math.isfinite(age) or not 0 <= age <= 1000):
                continue
            result['events'].append({'id': row['id'], 'sequence': row['sequence'],
                'event': 'attack', 'age_ms': age,
                'weapon_template': baseline.get('weapon_template', '') if row.get('weapon_id') == baseline.get('weapon_id') else ''})
    return result


def read(folder):
    try:
        with (folder / 'motion.json').open('rb') as file:
            raw = file.read(256 * 1024 + 1)
        return json.loads(raw) if len(raw) <= 256 * 1024 else {}
    except (OSError, ValueError):
        return {}
