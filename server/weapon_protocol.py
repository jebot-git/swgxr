"""Read server-resolved weapon profiles from authenticated Core3 attribute replies."""
import hashlib
import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.combat.export_catalog import parse_template, template_path
from server.profession_protocol import translate, player_context
from server.unarmed_protocol import player_stats
from server.character_protocol import skills
try:
    from .character_protocol import crc
    from .unarmed_protocol import unarmed_snapshot
except ImportError:
    from character_protocol import crc
    from unarmed_protocol import unarmed_snapshot
WEAPON_TYPE = 0x5745414F

def owned(record, objects, oid):
    parent = str(record.get('parentId', ''))
    seen = set()
    for _ in range(16):
        if parent == oid: return True
        if parent in seen: return False
        seen.add(parent)
        parent = str(objects.get('o'+parent, {}).get('parentId', ''))
    return False

def weapon_snapshots(result, oid):
    variables = result.get('variables', {})
    if variables.get('weapons', {}).get('complete') is not True:
        raise ValueError('Core3 weapon snapshot protocol is unavailable; rebuild core3client.')
    objects = variables.get('replication', {}).get('objects', {})
    player_record = objects.get('o'+str(oid), {})
    modifiers = player_stats(player_record)['skill_mods']
    learned = skills(player_record)
    attributes = variables.get('weaponAttributes', {})
    balance_path = ROOT/'client/combat/balance.json'
    config_path = ROOT/'server/combat/crafting_balance.json'
    balance = json.loads(balance_path.read_text())
    config = json.loads(config_path.read_text())
    revision = hashlib.sha256(balance_path.read_bytes()+config_path.read_bytes()).hexdigest()
    supported_crcs = {crc(str(Path(template_path(key, override)).with_name('shared_'+key+'.iff'))) for key, override in balance['weapons'].items()}
    weapons, unsupported = [], []
    for key, record in objects.items():
        if record.get('type') != WEAPON_TYPE or not owned(record, objects, oid): continue
        attr = attributes.get(key)
        if attr is None: raise ValueError('Missing Core3 weapon attributes: '+key)
        if 'swgxr.version' not in attr:
            if record.get('templateCrc') in supported_crcs:
                raise ValueError('Core3 crafting profile unavailable for supported weapon; rebuild the server.')
            unsupported.append(key.removeprefix('o'))
            continue
        if attr['swgxr.version'] != str(config['version']) or attr.get('swgxr.balance') != revision:
            raise ValueError('Core3/client weapon balance revision mismatch; rebuild the server.')
        if attr.get('swgxr.valid') != '1': raise ValueError('Core3 rejected invalid crafted weapon stats: '+key)
        weapon_id = attr.get('swgxr.id','')
        if weapon_id not in balance['weapons']:
            raise ValueError('Unsupported Core3 weapon profile: '+weapon_id)
        def number(name):
            if name not in attr: raise ValueError('Missing Core3 weapon attribute: '+name)
            value = float(attr[name])
            if not math.isfinite(value): raise ValueError('Non-finite Core3 weapon attribute: '+name)
            return value
        override = balance['weapons'][weapon_id]
        profile = dict(balance['classes'][override['class']], **override)
        template = template_path(weapon_id, override)
        profile.update(id=weapon_id, template=template,
                       core3=parse_template(ROOT/'vendor/Core3/MMOCoreORB/bin/scripts'/template.replace('.iff','.lua')))
        damage_types = {1:'kinetic',2:'energy',4:'blast',8:'stun',16:'lightsaber',32:'heat',64:'cold',128:'acid',256:'electricity'}
        damage_type = int(number('swgxr.damage_type'))
        if damage_type not in damage_types: raise ValueError('Unsupported Core3 weapon damage type')
        profile['core3']['damageType'] = damage_types[damage_type]
        profile['core3']['armorPiercing'] = int(number('swgxr.armor_piercing'))
        if attr.get('swgxr.combat_version') != '1':
            raise ValueError('Native armour/weapon conversion unavailable; rebuild Core3.')
        converted = {'version':1, 'revision':attr.get('swgxr.combat_revision','')}
        for field,attribute_name in (('base_type','swgxr.base_type'),('element_type','swgxr.element_type')):
            value = int(number(attribute_name))
            if value not in (1,2,32,64,128,256): raise ValueError('Invalid converted damage channel')
            converted[field] = damage_types[value]
        for field,attribute_name,minimum,maximum in (
            ('element_fraction','swgxr.element_fraction',0,.20),
            ('penetration','swgxr.penetration',0,.20),
            ('damage_scale','swgxr.damage_scale',.5,1)):
            value = number(attribute_name)
            if not minimum <= value <= maximum: raise ValueError('Invalid converted weapon '+field)
            converted[field] = value
        if len(converted['revision']) != 64 or any(c not in '0123456789abcdef' for c in converted['revision']):
            raise ValueError('Invalid native armour revision')
        profile['core3']['damage_profile'] = converted
        profile['armour_scales'] = {'output_scale':number('swgxr.armour_output_scale'),
                                    'recovery_scale':number('swgxr.capacity_recovery_scale')}
        if any(not .75 <= v <= 1 for v in profile['armour_scales'].values()):
            raise ValueError('Invalid native armour hindrance')

        for field, source in {'minDamage':'min_damage', 'maxDamage':'max_damage', 'woundsRatio':'wounds',
                              'pointBlankRange':'near_range', 'pointBlankAccuracy':'near_accuracy',
                              'idealRange':'ideal_range', 'idealAccuracy':'ideal_accuracy',
                              'maxRange':'max_range', 'maxRangeAccuracy':'max_accuracy'}.items():
            profile['core3'][field] = number('swgxr.'+source)
        if profile.get('kind') == 'melee':
            profile.update(stance_recovery=number('Stance recovery'), power=number('Power'),
                           crafting_modifiers={'stance_recovery':number('swgxr.stance_recovery_modifier'),
                                               'power':number('swgxr.power_modifier')})
            if profile['stance_recovery'] <= 0 or profile['power'] <= 0:
                raise ValueError('Invalid Core3 melee statistics')
        else:
            capacity = number('Capacity (shots)')
            if capacity != int(capacity) or capacity < 1: raise ValueError('Invalid Core3 capacity')
            profile.update(rpm=number('Rate of fire (RPM)'), capacity=int(capacity),
                           crafting_modifiers={'rpm':number('swgxr.rpm_modifier'), 'capacity':number('swgxr.capacity_modifier')})
            if profile['rpm'] <= 0: raise ValueError('Invalid Core3 rate of fire')
        profile.update(
                       source_kind='core3_weapon_instance', item_id=key.removeprefix('o'),
                       profile_version=config['version'], balance_revision=revision,
                       certified=attr.get('weapon_cert_status') == 'Yes',
                       crafting_raw={'attack_delay':number('swgxr.attack_delay'),
                                     'health_cost':number('swgxr.health_cost'), 'action_cost':number('swgxr.action_cost'),
                                     'mind_cost':number('swgxr.mind_cost')},
                       condition={'maxCondition':number('swgxr.max_condition'), 'conditionDamage':number('swgxr.condition_damage')})
        weapons.append(translate(profile, modifiers, learned))
    return {'backend':'core3', 'source':'authenticated_core3_attributes', 'character_id':oid,
            'profile_version':config['version'], 'balance_revision':revision,
            'weapons':sorted(weapons, key=lambda item:int(item['item_id'])), 'unsupported_item_ids':unsupported,
            'unarmed':unarmed_snapshot(result, oid), 'player_combat':player_context(result, oid),
            'combat_authority':'local_prediction_only', 'session':'validated_then_disconnected'}
