"""Unarmed VR tuning from owner-only Core3 CREO 1/4 replication, not skill guesses."""
import hashlib
import json
from pathlib import Path
try:
    from .character_protocol import Reader, skills
except ImportError:
    from character_protocol import Reader, skills
from tools.combat.export_catalog import parse_template

ROOT = Path(__file__).resolve().parents[1]
TEMPLATE = 'object/weapon/melee/unarmed/unarmed_default_player.iff'

def player_stats(record):
    if not record.get('baseline1') or not record.get('baseline4'):
        raise ValueError('Core3 player combat baselines unavailable; rebuild core3client.')
    base = Reader(bytes.fromhex(record['baseline1']))
    base.take(8)
    count = base.u32(); base.u32()
    if count != 9: raise ValueError('Invalid Core3 base HAM vector')
    ham = [base.number('i') for _ in range(count)]
    mods = Reader(bytes.fromhex(record['baseline4']))
    mods.take(8); mods.vector(4)
    count = mods.u32(); mods.u32()
    if count > 4096: raise ValueError('Invalid Core3 skill modifier count')
    totals = {}
    for _ in range(count):
        if mods.number('B') != 0: raise ValueError('Invalid Core3 skill modifier entry')
        key = mods.ascii().decode('ascii')
        value, bonus = mods.number('i'), mods.number('i')
        if key in totals: raise ValueError('Duplicate Core3 skill modifier')
        totals[key] = value + bonus
    if ham[1] < 0 or ham[4] < 0: raise ValueError('Invalid Core3 player attributes')
    return {'strength':ham[1], 'quickness':ham[4],
            'skill_mods':totals,
            'unarmed_damage':totals.get('unarmed_damage',0),
            'unarmed_speed':totals.get('unarmed_speed',0)}

def resolve(stats, character_id='', learned=None, source='core3_player_stats'):
    path = ROOT/'server/combat/unarmed_balance.json'
    config = json.loads(path.read_text())
    for key in ('strength','quickness','unarmed_damage','unarmed_speed'):
        if not isinstance(stats.get(key), (int,float)) or not -100000 <= stats[key] <= 100000:
            raise ValueError('Invalid unarmed player statistic: '+key)
    def bounded(value): return max(config['minimum_stat'], min(config['maximum_stat'],value))
    power = bounded(config['power_base'] + stats['strength']*config['strength_to_power'] + stats['unarmed_damage']*config['unarmed_damage_to_power'])
    recovery = bounded(config['recovery_base'] + stats['quickness']*config['quickness_to_recovery'] + stats['unarmed_speed']*config['unarmed_speed_to_recovery'])
    template = ROOT/'vendor/Core3/MMOCoreORB/bin/scripts'/TEMPLATE.replace('.iff','.lua')
    return {'id':'unarmed','label':'Unarmed','kind':'melee','unarmed':True,'hands':1,
            'power':power,'stance_recovery':recovery,
            **{key:config[key] for key in ('swing_speed_reference','swing_travel_reference','crouch_range_scale','prone_range_scale')},
            'two_hand_power_bonus':1.0,'one_hand_power_penalty':1.0,
            'core3':parse_template(template),'template':TEMPLATE,
            'source_kind':source,'character_id':str(character_id),'player_stats':dict(stats),
            'skills':list(learned or []),'certified':True,'profile_version':config['version'],
            'balance_revision':hashlib.sha256(path.read_bytes()+template.read_bytes()).hexdigest()}

def unarmed_snapshot(result, oid):
    record = result.get('variables',{}).get('replication',{}).get('objects',{}).get('o'+str(oid))
    if not record or record.get('type') != 0x4352454f:
        raise ValueError('Core3 selected player combat record unavailable')
    stats = player_stats(record)
    learned = skills(record)
    profile = resolve(stats, oid, learned)
    # Imported lazily to keep the original unarmed resolver usable by exporters.
    from server.profession_protocol import translate
    translate(profile, stats['skill_mods'], learned)
    return profile
