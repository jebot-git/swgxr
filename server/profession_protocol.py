"""Owner baseline skill translation and bounded frontend ability definitions.

No skill grants, persistent costs or combat authority. Costs are local prediction
inputs until an authenticated continuous combat session is implemented.
"""
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / 'server/combat/profession_balance.json'
SCRIPTS = ROOT / 'vendor/Core3/MMOCoreORB/bin/scripts'
ADVANCED = {'pistol':'pistol', 'carbine':'carbine', 'rifle':'rifleman',
            'onehandmelee':'1hsword', 'twohandmelee':'2hsword', 'polearm':'polearm', 'unarmed':'unarmed'}
BASIC = {'pistol':'marksman_pistol', 'carbine':'marksman_carbine', 'rifle':'marksman_rifle',
         'onehandmelee':'brawler_1handmelee', 'twohandmelee':'brawler_2handmelee',
         'polearm':'brawler_polearm', 'unarmed':'brawler_unarmed'}
COMMANDS = {'pistol':'overChargeShot2', 'carbine':'overChargeShot2', 'rifle':'overChargeShot2',
            'onehandmelee':'melee1hLunge2', 'twohandmelee':'melee2hLunge2',
            'polearm':'polearmLunge2', 'unarmed':'unarmedLunge2'}


def weapon_class(profile):
    if profile.get('unarmed'): return 'unarmed'
    # Commando's reusable rifles and pistol launcher retain their original
    # template folders; those folders must not grant Rifleman/Pistoleer bonuses.
    if profile.get('native_family') == 'commando': return 'heavy'
    parts = profile.get('template', '').split('/')
    for segment, kind in {'pistol':'pistol', 'carbine':'carbine', 'rifle':'rifle',
                          'knife':'onehandmelee', 'sword':'onehandmelee', 'baton':'onehandmelee',
                          'axe':'twohandmelee', '2h_sword':'twohandmelee', 'polearm':'polearm'}.items():
        if segment in parts: return kind
    return ''


def class_progress(kind, learned):
    if kind not in ADVANCED: return 0.0
    prefix = 'combat_' + ADVANCED[kind] + '_'
    learned = set(learned)
    if prefix + 'master' in learned: return 1.0
    basic = sum('combat_' + BASIC[kind] + '_0' + str(i) in learned for i in range(1, 5))
    advanced = sum(bool(re.fullmatch(re.escape(prefix) + r'(?:novice|(?:accuracy|speed|ability|support)_0[1-4])', skill)) for skill in learned)
    return min(1.0, (basic + advanced) / 22.0)


def literal(source, field):
    match = re.search(r'\b' + re.escape(field) + r'\s*=\s*([\d.]+)', source)
    if not match: raise ValueError('Missing source combat field: ' + field)
    return float(match[1])


def translate(profile, mods, learned):
    """Attach modifiers to unmodified item stats: refresh never stacks bonuses."""
    config = json.loads(CONFIG.read_text())
    kind = weapon_class(profile)
    accuracy = max(0, min(200, mods.get(kind + '_accuracy', 0))) if kind else 0
    speed = max(0, min(100, mods.get(kind + '_speed', 0))) if kind else 0
    melee = profile.get('kind') == 'melee'
    native_heavy = profile.get('native_family') == 'commando'
    # Accuracy remains source metadata; only enemy attacks use accuracy rolls.
    # Keep zeroed compatibility fields so older consumers cannot amplify contacts.
    tuning = {'weapon_class':kind, 'accuracy':accuracy, 'speed':speed,
              'class_progress':class_progress(kind, learned),
              'hit_radius':0,
              # Unarmed already includes speed in its Core3 player-stat resolver.
              'stance_recovery_scale':1.0 if profile.get('unarmed') else 1 + speed * config['melee_speed_recovery_per_point'] if melee else 1.0,
              'range_modifier_bonus':0,
              'rpm_scale':1 + speed * config['ranged_speed_rpm_per_point'] if not melee and not native_heavy else 1,
              'capacity_recovery_scale':1 + speed * config['ranged_speed_recovery_per_point'] if not melee and not native_heavy else 1,
              'balance_sha256':hashlib.sha256(CONFIG.read_bytes()).hexdigest()}
    profile['profession'] = tuning
    profile['abilities'] = []
    master = 'combat_brawler_master' if melee else 'combat_marksman_master'
    if kind not in COMMANDS or master not in learned: return profile
    command = COMMANDS[kind]
    path = SCRIPTS / ('commands/' + command + '.lua')
    source = path.read_text()
    raw = profile.get('crafting_raw')
    if raw is None:
        weapon = (SCRIPTS / profile['template'].replace('.iff', '.lua')).read_text()
        raw = {pool + '_cost':literal(weapon, pool + 'AttackCost') for pool in ('health','action','mind')}
    ability = {'id':'melee_assault' if melee else 'lethal_shot', 'label':'Melee Assault' if melee else 'Lethal Shot',
               'source_command':command.lower(), 'source_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
               'damage_multiplier':literal(source, 'damageMultiplier'),
               'base_sac':{pool:raw[pool + '_cost'] * literal(source, pool + 'CostMultiplier') for pool in ('health','action','mind')},
               'cooldown_seconds':config['ability_base_cooldown_seconds'] * (1 - config['ability_master_cooldown_reduction'] * tuning['class_progress']),
               'knockdown_chance':config['ability_knockdown_chance'], 'required_skill':master}
    profile['abilities'] = [ability]
    return profile


def player_context(result, oid):
    from server.combat_protocol import baseline
    record = result.get('variables', {}).get('replication', {}).get('objects', {}).get('o' + str(oid), {})
    observation = baseline(record)
    return {'character_id':str(oid), 'ham':observation.get('ham', {}).get('values', []),
            'max_ham':observation.get('max_ham', {}).get('values', []),
            'wounds':observation.get('wounds', {}).get('values', []),
            'posture':observation.get('posture', 0),
            'complete':observation.get('complete', False), 'source':'core3_entry_observation',
            'combat_authority':'local_prediction_only'}
