"""Validated original entertainer commands; Core3 owns effects, skills and XP."""
import math
import re
from copy import deepcopy
try:
    from .planets import context as planet_context
    from .entertainment_catalog import catalog
except ImportError:
    from planets import context as planet_context
    from entertainment_catalog import catalog

ACTIONS = ('status', 'perform', 'stop', 'flourish', 'register_location', 'group_invite', 'group_join', 'group_leave', 'group_bump')


def audience_snapshot(value):
    """Bound native audience observations; presence never supplies these values."""
    if not isinstance(value, dict) or value.get('policy') != 'automatic_radius':
        raise ValueError('Invalid native audience policy.')
    radius = value.get('radius_m')
    if type(radius) not in (int, float) or not math.isfinite(radius) or radius != 8:
        raise ValueError('Invalid native audience radius.')
    for key, expected in (('minimum_seconds', 60), ('refresh_seconds', 10)):
        if type(value.get(key)) is not int or value[key] != expected:
            raise ValueError('Invalid native audience timing.')
    sources = value.get('sources')
    if not isinstance(sources, list) or len(sources) > 2:
        raise ValueError('Native audience sources exceed bounds.')
    rows, kinds, identities = [], set(), set()
    for source in sources:
        if not isinstance(source, dict):
            raise ValueError('Invalid native audience source.')
        oid, kind = source.get('id'), source.get('kind')
        if (not isinstance(oid, str) or not re.fullmatch(r'[0-9]{1,20}', oid)
                or not 0 < int(oid) < 2**64 or kind not in ('dance', 'music')
                or kind in kinds or oid in identities):
            raise ValueError('Invalid or duplicate native audience source.')
        row = {'id': oid, 'kind': kind}
        for key in ('seconds', 'strength', 'duration_minutes'):
            number = source.get(key)
            if type(number) is not int or not 0 <= number <= 2**31 - 1:
                raise ValueError('Invalid native audience progress.')
            row[key] = number
        rows.append(row); kinds.add(kind); identities.add(oid)
    return {'policy': 'automatic_radius', 'radius_m': float(radius),
            'minimum_seconds': 60, 'refresh_seconds': 10, 'sources': rows}


def command(action, data):
    if action not in ACTIONS and not action.startswith('image_'):
        raise ValueError('Unsupported entertainer action.')
    out = {'action': action, **planet_context(data)}
    if action != 'status':
        key = data.get('request_id', '')
        if not isinstance(key, str) or not re.fullmatch(r'[A-Za-z0-9_-]{8,64}', key):
            raise ValueError('Stable entertainer request_id required.')
        out['request_id'] = key
    if 'position' in data:
        position = data['position']
        if not isinstance(position, list) or len(position) != 3 or any(type(v) not in (int, float) or not math.isfinite(v) or abs(v) > (2048 if i == 1 else 8192) for i, v in enumerate(position)):
            raise ValueError('Finite source position required.')
        out['position'] = position
    if 'building_id' in data:
        building, cell = data['building_id'], data.get('cell_index')
        if not isinstance(building, str) or not re.fullmatch(r'[0-9]{1,20}', building) or int(building) >= 2**64 or type(cell) is not int or not 0 <= cell <= 256 or ((int(building) == 0) != (cell == 0)):
            raise ValueError('Original source building and cell required.')
        out.update(building_id=building, cell_index=cell)
    if action in ('group_invite', 'group_bump'):
        target=data.get('target_id')
        if not isinstance(target,str) or not re.fullmatch(r'[0-9]{1,20}',target) or not 0<int(target)<2**64:raise ValueError('Native group invite target required.')
        out['target_id']=target
    if action == 'group_bump':
        proof=data.get('group_bump_id')
        if not isinstance(proof,str) or not re.fullmatch(r'[0-9a-f]{24}',proof):raise ValueError('Server-issued fist bump ID required.')
        out['group_bump_id']=proof
    if action == 'perform':
        performance = catalog()['performances'].get(data.get('performance_id'))
        if performance is None:
            kind, name = data.get('kind'), data.get('name')
            performance = next((p for p in catalog()['performances'].values() if p['kind'] == kind and p['name'] == name), None)
        if performance is None:
            raise ValueError('Original performance selection required.')
        out.update(kind=performance['kind'], name=performance['name'])
        if out['kind'] == 'music':
            item = data.get('item_id')
            if not isinstance(item, str) or not re.fullmatch(r'[0-9]{1,20}', item) or not 0 < int(item) < 2**64:
                raise ValueError('Native equipped or placed instrument required.')
            out['item_id'] = item
    if action.startswith('image_'):
        try:
            from .image_design_protocol import command as image_command
        except ImportError:
            from image_design_protocol import command as image_command
        out.update(image_command(action, data))
    # No client index/effect/XP/skill or claimed gesture duration is forwarded.
    return out


def snapshot(value, character_id):
    out = deepcopy(value)
    if out.get('error'):
        raise ValueError(out['error'])
    if out.get('source_kind') != 'core3_entertainer' or out.get('character_id') != str(character_id):
        raise ValueError('Owned native entertainer response required.')
    state = out.get('state', {})
    if state.get('character_id') != str(character_id) or len(state.get('flourishes', [])) > 8 or len(state.get('flourish_choices', [])) > 15 or len(state.get('commands', [])) > 4096:
        raise ValueError('Invalid native entertainer state.')
    if len(state.get('registrations',[]))>256 or any(len(state.get(key,[]))>32 for key in ('nearby_players','group_candidates')):
        raise ValueError('Native entertainer public state exceeds bounds.')
    if 'audience' in state:
        state['audience'] = audience_snapshot(state['audience'])
    out['ok'] = out.get('mutation', {}).get('success') is True
    return out
