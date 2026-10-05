"""Bounded, authenticated Core3 inventory snapshots; never a local item store."""
from copy import deepcopy
try:
    from .character_protocol import template_names, decode_customization
    from .datapad_protocol import display, template_label
except ImportError:
    from character_protocol import template_names, decode_customization
    from datapad_protocol import display, template_label


def inventory_snapshot(result, oid):
    variables = result.get('variables', {})
    snapshot = deepcopy(variables.get('inventory', {}))
    if snapshot.get('error'):
        raise ValueError(snapshot['error'])
    if snapshot.get('source_kind') != 'core3_inventory' or snapshot.get('character_id') != str(oid):
        raise ValueError('Core3 inventory snapshot is missing or belongs to another character.')
    items, containers = snapshot.get('items'), snapshot.get('containers')
    if not isinstance(items, list) or not isinstance(containers, list) or len(items) > 256 or len(containers) > 256:
        raise ValueError('Core3 inventory snapshot exceeds bounds.')
    root = snapshot.get('inventory', {})
    if not str(root.get('id', '')).isdigit():
        raise ValueError('Core3 inventory root is missing.')
    ids = {item.get('id') for item in items}
    if len(ids) != len(items) or any(not isinstance(i, str) or not i.isdigit() for i in ids):
        raise ValueError('Invalid or duplicate inventory item identifiers.')
    names = template_names()
    attributes = variables.get('weaponAttributes', {})
    container_ids = {container['id'] for container in containers}
    if root['id'] not in container_ids:
        raise ValueError('Inventory root container is not present.')
    for container in containers:
        if not 0 <= container.get('depth', -1) <= 8 or container.get('capacity', -1) < 0 or container.get('occupied', -1) < 0:
            raise ValueError('Invalid Core3 container capacity or depth.')
        if len(container.get('item_ids', [])) != container.get('direct_count'):
            raise ValueError('Core3 container contents are incomplete.')
        if any(i not in ids for i in container['item_ids']):
            raise ValueError('Core3 container references missing items.')
    for item in items:
        if item['container_id'] not in container_ids and not (item.get('equipped') and item['container_id'] == str(oid)):
            raise ValueError('Item is outside the selected inventory hierarchy.')
        if item.get('quantity', 0) < 1:
            raise ValueError('Invalid Core3 item quantity.')
        item['shared_template'] = names.get(item.get('client_crc'), '')
        item['customization'] = decode_customization(bytes.fromhex(item.get('customization_hex', '')))
        fallback = template_label(item['shared_template'] or item['template'])[0]
        item['name'] = item.pop('custom_name', '') or display(item.pop('name_table', ''), item.pop('name_key', ''), fallback)
        description = item.get('description', '')
        if description.startswith('@') and ':' in description:
            table, key = description[1:].split(':', 1)
            item['description'] = display(table, key, description)
        attr = attributes.get('o'+item['id'])
        if attr is None:
            raise ValueError('Missing Core3 item attributes: '+item['id'])
        item['attributes'] = [{'name': key, 'value': value} for key, value in attr.items() if not key.startswith('swgxr.')]
    by_id = {item['id']: item for item in items}
    bag = snapshot.get('equipped_backpack')
    snapshot['equipped_backpack'] = by_id.get(bag['id']) if bag else None
    snapshot['equipment'] = [by_id[item['id']] for item in snapshot.get('equipment', [])]
    snapshot['race'] = snapshot.get('species_template', '').rsplit('/', 1)[-1].removesuffix('.iff').removeprefix('shared_')
    for container in containers:
        container['name'] = by_id.get(container['id'], {}).get('name', 'Inventory')
    snapshot.update(backend='core3', session='authenticated_snapshot_then_disconnected', limits={'max_items':256,'max_depth':8})
    return snapshot
