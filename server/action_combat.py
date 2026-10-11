"""Bounded prototype commands and native-only action presentation."""
import math,re


def command(value):
    if not isinstance(value, dict):
        raise ValueError('Action combat intent required')
    op = value.get('action')
    if op == 'negotiate':
        if set(value) != {'action', 'protocol', 'catalog_revision'} or type(value['protocol']) is not int or value['protocol'] != 2 or not isinstance(value['catalog_revision'], str) or len(value['catalog_revision']) != 64 or any(c not in '0123456789abcdef' for c in value['catalog_revision']):
            raise ValueError('Invalid ground capability')
        return dict(value)
    if op == 'batch':
        if set(value) != {'action', 'receipts'} or not isinstance(value['receipts'], list) or len(value['receipts']) > 32:
            raise ValueError('Invalid ground receipt batch')
        for row in value['receipts']:
            keys = {'kind', 'actor_id', 'attack_id', 'aim_revision'}
            if not isinstance(row, dict) or row.get('kind') not in ('warning', 'lock', 'contact'):
                raise ValueError('Invalid ground receipt')
            if row['kind'] == 'contact': keys |= {'contact', 'coverage_start', 'coverage_end', 'sample_position'}
            if row['kind'] == 'contact' and 'contact_at' in row:
                keys.add('contact_at')
                if row.get('contact') is not True or type(row['contact_at']) not in (int,float) or not math.isfinite(row['contact_at']) or row['contact_at'] < 0: raise ValueError('Invalid positive contact time')
            if row['kind'] != 'contact' and 'presented_at' in row:
                keys.add('presented_at')
                if type(row['presented_at']) not in (int,float) or not math.isfinite(row['presented_at']) or row['presented_at'] < 0: raise ValueError('Invalid presentation time')
            if set(row) != keys: raise ValueError('Unexpected ground receipt fields')
            for key in ('actor_id', 'attack_id'):
                v = row[key]
                if not isinstance(v, str) or not v.isascii() or not v.isdecimal() or not 0 < int(v) < 2**64: raise ValueError('Invalid ground identity')
            if type(row['aim_revision']) is not int or not 0 < row['aim_revision'] < 2**53: raise ValueError('Invalid ground revision')
            if row['kind'] == 'contact':
                command(dict(action='contact',encounter_id=row['actor_id'],**{k:row[k] for k in ('actor_id','attack_id','aim_revision','contact','coverage_start','coverage_end')}))
                v = row['sample_position']
                if not isinstance(v,list) or len(v)!=3 or any(type(x) not in (int,float) or not math.isfinite(x) or abs(x)>20000 for x in v): raise ValueError('Invalid ground sample')
        return dict(value)
    if op in ('join', 'leave') or op == 'status' and 'encounter_id' in value:
        v = value.get('encounter_id')
        if set(value) != {'action', 'encounter_id'} or not isinstance(v, str) or not v.isascii() or not v.isdecimal() or not 0 < int(v) < 2**64:
            raise ValueError('Invalid encounter identity')
        return dict(value)
    if op in ('start', 'status', 'stop'):
        if set(value) != {'action'}:
            raise ValueError('Unexpected action combat fields')
        return {'action': op}
    keys = {'action', 'encounter_id', 'actor_id', 'attack_id', 'contact',
            'coverage_start', 'coverage_end', 'aim_revision'}
    if op != 'contact' or set(value) != keys:
        raise ValueError('Invalid action contact fields')
    for key in ('encounter_id', 'actor_id', 'attack_id'):
        v = value[key]
        if not isinstance(v, str) or not v.isascii() or not v.isdecimal() or not 0 < int(v) < 2**64:
            raise ValueError('Invalid action contact identity')
    if type(value['contact']) is not bool:
        raise ValueError('Invalid action contact')
    if type(value['aim_revision']) is not int or not 0 < value['aim_revision'] < 2**53:
        raise ValueError('Invalid action aim revision')
    for key in ('coverage_start', 'coverage_end'):
        if type(value[key]) not in (int, float) or not math.isfinite(value[key]) or value[key] < 0:
            raise ValueError('Invalid action contact time')
    if not 0 <= value['coverage_end'] - value['coverage_start'] <= 30:
        raise ValueError('Invalid action coverage')
    return dict(value)


def events(stream, visible, elapsed):
    rows = stream.get('action_events', [])
    if not isinstance(rows, list) or len(rows) > 64:
        return []
    result = []
    for row in rows:
        if not isinstance(row, dict):
            continue
        actor = visible.get(row.get('id'))
        if not actor or actor.get('cell_id', '0') != row.get('cell_id'):
            continue
        if row.get('phase') not in ('windup', 'active', 'recovery', 'cancelled') or row.get('role') not in ('melee', 'ranged', 'support'):
            continue
        if (actor.get('dead') or actor.get('incapacitated')) and row['phase'] != 'cancelled':
            continue
        if any(type(row.get(k)) not in (int, float) or not math.isfinite(row[k]) for k in
               ('server_now', 'start', 'active_at', 'end_at', 'recover_at', 'range', 'radius', 'cosine', 'age_ms')):
            continue
        if any(not isinstance(row.get(k), str) or not row[k].isascii() or not row[k].isdecimal() or not 0 < int(row[k]) < 2**64
               for k in ('encounter_id', 'attack_id', 'target_id')):
            continue
        if type(row.get('sequence')) is not int or not 0 <= row['sequence'] < 2**53:
            continue
        if not row['start'] <= row['active_at'] <= row['end_at'] <= row['recover_at'] <= row['start'] + 30:
            continue
        if 'eligible_victim_ids' in row or 'hit_policy' in row:
            victims = row.get('eligible_victim_ids')
            if not isinstance(victims, list) or len(victims) > (256 if row.get('protocol') == 2 else 8) or any(not isinstance(v, str) or not v.isascii() or not v.isdecimal() or not 0 < int(v) < 2**64 for v in victims):
                continue
            policies = {'melee': ('cleave',), 'ranged': ('piercing_lane',), 'support': ('support',)}
            if row.get('protocol') == 2:
                policies['ranged'] = ('first_contact',)
            allowed = policies[row['role']]
            if row.get('protocol') == 2 and 'shape' in row:
                allowed = {'targeted': ('targeted',), 'cone': ('cleave',), 'circle': ('cleave',), 'lane': ('first_contact',)}.get(row['shape'], ())
            if len(set(victims)) != len(victims) or row.get('hit_policy') not in allowed:
                continue
            if row['role'] == 'support' and victims:
                continue
        if 'shape' in row:
            if row['shape'] not in ('lane','cone','circle','targeted') or type(row.get('special')) is not bool or type(row.get('target_required')) is not bool:continue
            center=row.get('geometry_origin')
            if not isinstance(center,list) or len(center)!=3 or any(type(x) not in (int,float) or not math.isfinite(x) or abs(x)>20000 for x in center):continue
            if row['shape']=='targeted' and (not row['target_required'] or row.get('eligible_victim_ids')!=[row['target_id']]):continue
        if 'animation' in row:
            expected = {'melee': ['action_worrt'], 'ranged': ['action_pistol'], 'support': ['action_heal']}[row['role']]
            if row.get('protocol') == 2:
                if type(row.get('state_revision')) is not int or not 0 < row['state_revision'] < 2**53: continue
                expected = ['action_ground_'+s for s in (('pistol','rifle','carbine','ranged') if row['role']=='ranged' else ('creature','unarmed','onehand','twohand','polearm'))]
            special_animation=row.get('protocol')==2 and row.get('special') is True and isinstance(row.get('animation'),str) and re.fullmatch(r'action_ground_special_[0-9a-f]{24}',row['animation']) is not None
            if (row['animation'] not in expected and not special_animation) or any(type(row.get(k)) not in (int, float) or not math.isfinite(row[k]) for k in ('delivery_at', 'animation_end_at')):
                continue
            if not row['start'] <= row['delivery_at'] <= row['active_at'] or not row['delivery_at'] < row['animation_end_at'] <= row['recover_at']:
                continue
        if any(k in row for k in ('aim_revision', 'aim_locked', 'lock_at')):
            if type(row.get('aim_revision')) is not int or not 0 < row['aim_revision'] < 2**53 or type(row.get('aim_locked')) is not bool:
                continue
            if type(row.get('lock_at')) not in (int, float) or not math.isfinite(row['lock_at']) or not row['start'] <= row['lock_at'] <= row.get('delivery_at', row['active_at']):
                continue
            if row['phase'] in ('active', 'recovery') and not row['aim_locked']:
                continue
        if not 0 < row['range'] <= (96 if row.get('protocol') == 2 else 32) or not 0 <= row['radius'] <= 2 or not -1 <= row['cosine'] <= 1:
            continue
        if any(not isinstance(row.get(k), list) or len(row[k]) != 3 or any(type(x) not in (int, float) or not math.isfinite(x) or abs(x) > 20000 for x in row[k]) for k in ('origin', 'direction')):
            continue
        if abs(sum(x*x for x in row['direction']) - 1) > .05:
            continue
        age = row['age_ms'] + max(0, elapsed)
        if not 0 <= age <= 5000:
            continue
        result.append(dict(row, age_ms=age))
    return result
