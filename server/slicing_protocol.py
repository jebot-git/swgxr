"""Bounded physical slicing input; Core3 owns puzzles, locks and outcomes."""
import math
import re

ACTIONS = tuple('slicing_' + action for action in ('status', 'begin', 'complete', 'cancel'))


def position(value, name):
    if (not isinstance(value, list) or len(value) != 3 or
            any(type(v) not in (int, float) or not math.isfinite(v) or
                abs(v) > (2048 if i == 1 else 8192) for i, v in enumerate(value))):
        raise ValueError('Finite slicing ' + name + ' required.')
    return list(value)


def fields(action, data):
    out = {}
    if action == 'slicing_begin':
        for name in ('tool_id', 'target_id'):
            value = data.get(name)
            if not isinstance(value, str) or not value.isascii() or not value.isdigit() or not 0 < int(value) < 2**64:
                raise ValueError('Native slicing ' + name + ' required.')
            out[name] = value
        kind = data.get('target_kind')
        if kind not in ('item', 'terminal'):
            raise ValueError('Slicing target must be an item or terminal.')
        out['target_kind'] = kind
        for name in ('tool_position', 'anchor_position') + (('target_position',) if kind == 'item' else ()):
            out[name] = position(data.get(name), name)
        heading = data.get('heading_radians')
        if type(heading) not in (int, float) or not math.isfinite(heading) or abs(heading) > math.tau:
            raise ValueError('Finite slicing heading required.')
        out['heading_radians'] = heading
        return out
    attempt = data.get('attempt_id', '')
    if action == 'slicing_status' and attempt == '':
        return out
    if not isinstance(attempt, str) or not re.fullmatch(r'[A-Za-z0-9_-]{8,64}', attempt):
        raise ValueError('Current native slicing attempt required.')
    out['attempt_id'] = attempt
    if action == 'slicing_complete':
        paths = data.get('paths')
        if not isinstance(paths, list) or not 2 <= len(paths) <= 4:
            raise ValueError('Two to four slicing paths required.')
        colors, occupied, result = set(), set(), []
        for path in paths:
            if not isinstance(path, dict) or set(path) != {'color', 'cells'}:
                raise ValueError('Slicing paths require color and cells.')
            color, cells = path['color'], path['cells']
            if type(color) is not int or not 0 <= color <= 3 or color in colors:
                raise ValueError('Unique slicing path colors required.')
            if not isinstance(cells, list) or not 2 <= len(cells) <= 125:
                raise ValueError('Bounded slicing cell path required.')
            previous = None
            for cell in cells:
                if not isinstance(cell, list) or len(cell) != 3 or any(type(v) is not int or not 0 <= v <= 4 for v in cell):
                    raise ValueError('Integer slicing grid coordinates required.')
                point = tuple(cell)
                if point in occupied or (previous is not None and sum(abs(a-b) for a, b in zip(point, previous)) != 1):
                    raise ValueError('Slicing paths must be adjacent and cannot cross.')
                occupied.add(point)
                previous = point
            colors.add(color)
            result.append({'color': color, 'cells': [list(cell) for cell in cells]})
        # The exact board size, endpoint pairs, timer and ownership remain native.
        out['paths'] = result
    return out
