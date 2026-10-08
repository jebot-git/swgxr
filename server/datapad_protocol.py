"""Owner-only datapad state decoded from actual Core3 PLAY8/9 replication.

Waypoints are persistent PlayerObject records, not simulated local inventory.
Learned draft schematics are distinct from physical manufacturing schematics.
"""
from functools import lru_cache
from copy import deepcopy
from pathlib import Path
try:
    from .character_protocol import Reader, assets, template_names, crc, parse_iff, cstring, skills
except ImportError:
    from character_protocol import Reader, assets, template_names, crc, parse_iff, cstring, skills
from stf import string_table

try:
 from .planets import SUPPORTED_PLANETS
except ImportError:
 from planets import SUPPORTED_PLANETS
PLANETS = list(SUPPORTED_PLANETS)

@lru_cache(maxsize=64)
def labels(table):
    path='string/en/'+table+'.stf'
    return string_table(assets().read(path)) if path in assets().entries else {}

def display(table,key,fallback):
    return labels(table).get(key,fallback) if table and key else fallback

@lru_cache(maxsize=1024)
def template_label(template):
    fallback=Path(template).stem.removeprefix('shared_').replace('_',' ').title()
    if template in assets().entries:
        for entry in parse_iff(assets().read(template)).walk('XXXX'):
            if entry.data.startswith(b'objectName\0\1\1'):
                table,pos=cstring(entry.data,len(b'objectName\0\1\1'));key,_=cstring(entry.data,pos+1)
                return display(table,key,fallback),{'table':table,'key':key}
    return fallback,{}

def count(reader):
    value=reader.u32();reader.u32()
    if value>10000:raise ValueError('Invalid Core3 datapad list size.')
    return value

def owner_summary(result, oid):
    """Use the existing owned native request; absent is unknown, never zero."""
    variables = result.get('variables', {})
    summary = variables.get('player_summary')
    if summary is None:
        summary = variables.get('session', {}).get('player_summary')
    if summary is None:
        return None
    return normalize_summary(summary, oid)

def normalize_summary(summary, oid):
    if (not isinstance(summary, dict) or summary.get('version') != 1
            or summary.get('character_id') != str(oid)):
        raise ValueError('Native player summary does not identify the selected character.')
    summary = deepcopy(summary)
    rows = list(summary.get('homepoints', {}).values()) + summary.get('armour', {}).get('pieces', [])
    for row in rows:
        name = row.get('name', '')
        if isinstance(name, str) and name.startswith('@') and ':' in name:
            table, key = name[1:].split(':', 1)
            row['name'] = display(table, key, key.replace('_', ' ').title())
    return summary

def datapad(result,oid):
    objects=result.get('variables',{}).get('replication',{}).get('objects',{})
    owned={key[1:]:record for key,record in objects.items() if record.get('parentId')==str(oid)}
    ghost=next((r for r in owned.values() if r.get('type')==0x504c4159),None)
    if not ghost or not ghost.get('baseline8') or not ghost.get('baseline9'):
        raise ValueError('Core3 did not replicate the selected player datapad baseline.')
    names=template_names();waypoints=[];recipes=[];entries=[]
    r=Reader(bytes.fromhex(ghost['baseline8']))
    experience={}
    for _ in range(count(r)):
        r.take(1);xp_type=r.ascii().decode();experience[xp_type]=r.number('i')
    for _ in range(count(r)):
        r.take(1);map_id=r.u64();cell=r.u32()
        position=[r.number('f') for _ in range(3)]
        r.u64();planet_crc=r.u32();name=r.unicode();waypoint_id=r.u64();color=r.number('B');active=bool(r.number('B'))
        if map_id!=waypoint_id:raise ValueError('Core3 waypoint map/object identifiers disagree.')
        waypoints.append({'id':str(waypoint_id),'category':'waypoints','name':name,'planet':next((p for p in PLANETS if crc(p)==planet_crc),''),'position':position,'active':active,'icon':'waypoint','attributes':{'color':color,'cell_id':str(cell),'planet_crc':planet_crc},'source':'core3_player_waypoint_list'})
    r=Reader(bytes.fromhex(ghost['baseline9']))
    for _ in range(count(r)):r.ascii()
    r.take(16)
    for _ in range(count(r)):
        identifier=r.u32();duplicate=r.u32()
        if identifier!=duplicate:raise ValueError('Unexpected Core3 schematic wire format.')
        template=names.get(identifier,'');label,stringid=template_label(template) if template else ('Draft schematic '+str(identifier),{})
        recipes.append({'id':'schematic:'+str(identifier),'category':'schematics','name':label,'template':template,'name_string_id':stringid,'description':'Learned crafting recipe granted by Core3 player skills.','attributes':{'client_template_crc':identifier,'kind':'learned_draft_schematic'},'source':'core3_player_schematic_list'})
    container=next((key for key,r in owned.items() if names.get(r.get('templateCrc'),'').endswith('/shared_character_datapad.iff')),None)
    if container is None:raise ValueError('Core3 did not replicate this character’s datapad container.')
    for key,record in objects.items():
        if record.get('parentId')!=container or not record.get('baseline3'):continue
        template=names.get(record.get('templateCrc'),'');r=Reader(bytes.fromhex(record['baseline3']))
        r.take(4);table=r.ascii().decode();r.u32();entry_key=r.ascii().decode();custom=r.unicode();r.u32()
        fallback=template_label(template)[0] if template else 'Datapad object '+key[1:]
        category='vehicles' if '/vehicle/' in template else 'pets' if '/pet/' in template else 'schematics' if 'schematic' in template else 'data'
        entries.append({'id':key[1:],'category':category,'name':custom or display(table,entry_key,fallback),'template':template,'name_string_id':{'table':table,'key':entry_key},'attributes':{'container_id':container,'template_crc':record.get('templateCrc')},'source':'core3_datapad_container'})
    attributes = result.get('variables', {}).get('weaponAttributes', {})
    for entry in waypoints+entries:
        entry['deletable'] = attributes.get('o'+entry['id'], {}).get('swgxr.deletable') == '1'
        entry['deletion_reason'] = '' if entry['deletable'] else 'Static, protected or server-managed entry'
    for entry in recipes:
        entry['deletable'] = False
        entry['deletion_reason'] = 'Learned recipe managed by Core3 skills'
    player = objects.get('o'+str(oid), {})
    return {'backend':'core3','character_id':str(oid),'container_id':container,'entries':waypoints+entries+recipes,'waypoints':waypoints,'schematics':recipes,'physical_entries':entries,'source':'core3_replication','position_space':'swg_world_xyz_y_up',
            'skills':skills(player), 'skills_complete':bool(player.get('baseline1')),
            'experience':experience,'experience_complete':True,
            'player_summary':owner_summary(result, oid)}
