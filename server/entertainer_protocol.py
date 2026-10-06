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

ACTIONS = ('status', 'perform', 'stop', 'flourish', 'register_location', 'group_invite', 'group_join', 'group_leave')


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
    if action == 'group_invite':
        target=data.get('target_id')
        if not isinstance(target,str) or not re.fullmatch(r'[0-9]{1,20}',target) or not 0<int(target)<2**64:raise ValueError('Native group invite target required.')
        out['target_id']=target
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
                raise ValueError('Owned native instrument required.')
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
    out['ok'] = out.get('mutation', {}).get('success') is True
    return out
