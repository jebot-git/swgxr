"""Bounded image-design requests and source-derived previews; Core3 commits changes."""
import copy
import math
import re
try:
    from .character_protocol import decode_customization, race_from_template
    from .image_design_catalog import options, proposal
except ImportError:
    from character_protocol import decode_customization, race_from_template
    from image_design_catalog import options, proposal

ACTIONS = ('image_open', 'image_propose', 'image_accept', 'image_cancel')


def command(action, data):
    out = {}
    if action not in ACTIONS:
        raise ValueError('Unsupported image design action.')
    if action == 'image_open':
        value = data.get('target_id')
        if not isinstance(value, str) or not value.isdigit() or not 0 < int(value) < 2**64:
            raise ValueError('Valid image design recipient required.')
        return {'target_id': value}
    session = data.get('session_id')
    if not isinstance(session, str) or not re.fullmatch(r'[0-9]{1,20}', session):
        raise ValueError('Original image design session required.')
    revision = data.get('revision')
    if type(revision) is not int or not 0 <= revision < 2**31:
        raise ValueError('Current image design revision required.')
    out.update(session_id=session, revision=revision)
    if action == 'image_propose':
        draft = data.get('draft')
        if not isinstance(draft, dict) or set(draft) - {'attributes','hair_template','holoemote','price'}:
            raise ValueError('Invalid image design draft.')
        attributes = draft.get('attributes', {})
        if not isinstance(attributes, dict) or len(attributes) > 128:
            raise ValueError('Invalid image design attributes.')
        for key, value in attributes.items():
            if not isinstance(key, str) or not re.fullmatch(r'[A-Za-z0-9_]{1,80}', key) or type(value) not in (int,float) or not math.isfinite(value):
                raise ValueError('Invalid image design attribute.')
        price = draft.get('price', 0)
        if type(price) is not int or not 0 <= price <= 10000:
            raise ValueError('Image design price must be between 0 and 10000.')
        for field in ('hair_template','holoemote'):
            if field in draft and (not isinstance(draft[field], str) or len(draft[field]) > 256):
                raise ValueError('Invalid '+field)
        out['draft'] = copy.deepcopy(draft)
    return out


def normalize_appearance(raw):
    appearance = copy.deepcopy(raw)
    species, sex, race = race_from_template(appearance['template'])
    appearance.update(species=species, sex=sex, race=race,
                      customization=decode_customization(bytes.fromhex(appearance.pop('customization_hex',''))))
    hair = appearance.pop('hair_template','')
    hair_colors = decode_customization(bytes.fromhex(appearance.pop('hair_customization_hex','')))
    appearance['hair'] = {'template':hair,'customization':hair_colors} if hair else None
    for item in appearance.get('equipment', []):
        item['customization'] = decode_customization(bytes.fromhex(item.pop('customization_hex','')))
    appearance['source'] = 'core3_image_design'
    return appearance


def normalize(raw):
    value = copy.deepcopy(raw)
    if not value.get('active'):
        return value
    appearance = normalize_appearance(value['appearance'])
    value['appearance'] = appearance
    designer = value['designer_context']
    value['options'] = options(designer, appearance)
    value['preview'] = proposal(designer, appearance, value.get('draft',{}))['preview']
    return value
