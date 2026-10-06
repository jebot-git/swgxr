"""Original performance definitions and skill grants; no invented learned skills."""
from functools import lru_cache
from pathlib import Path
import hashlib
import re
try:
    from .character_protocol import assets, skills
except ImportError:
    from character_protocol import assets, skills
from character_formats import datatable

ROOT = Path(__file__).resolve().parents[1]
INSTRUMENTS = {'slitherhorn':('slitherhorn','wind',3), 'fizz':('fizz','wind',3),
    'fanfar':('fanfar','wind',3), 'kloo_horn':('kloohorn','wind',3),
    'flute_droopy':('flutedroopy','wind',3), 'traz':('traz','strings',3),
    'mandoviol':('mandoviol','strings',5), 'bandfill':('bandfill','percussion',1),
    'ommni_box':('omnibox','percussion',4), 'nalargon':('nalargon','keyboard',2)}

@lru_cache(maxsize=1)
def catalog():
    source = 'datatables/performance/performance.iff'
    raw = assets().read(source)
    provenance = {source:hashlib.sha256(raw).hexdigest()}
    rows = datatable(raw)
    skill_source = 'datatables/skill/skills.iff'
    raw_skills = assets().read(skill_source)
    provenance[skill_source] = hashlib.sha256(raw_skills).hexdigest()
    grants = {r['NAME']:list(filter(None, r['COMMANDS'].split(','))) for r in datatable(raw_skills)}
    items = {}
    for name, (instrument, gesture, animation) in INSTRUMENTS.items():
        template = 'object/tangible/instrument/' + name + '.iff'
        path = ROOT/'vendor/Core3/MMOCoreORB/bin/scripts'/template.replace('.iff','.lua')
        raw = path.read_bytes()
        provenance[str(path.relative_to(ROOT))] = hashlib.sha256(raw).hexdigest()
        audio_id = int(re.search(rb'instrumentType\s*=\s*(\d+)',raw)[1])
        items[template] = {'instrument':instrument, 'gesture':gesture, 'animation':'music_'+str(animation), 'audio_id':audio_id}
    performances = {}
    for index, row in enumerate(rows, 1):
        dance = bool(row['requiredDance'])
        kind = 'dance' if dance else 'music'
        instrument = 'dance' if dance else row['requiredInstrument']
        key = kind+':'+row['performanceName'].lower()+':'+instrument
        animation = 'dance_'+str(row['danceVisualId']) if dance else next(v['animation'] for v in items.values() if v['instrument']==instrument)
        performances[key] = {'id':key, 'label':row['performanceName'].replace('_',' ').capitalize(),
            'name':row['performanceName'].lower(), 'kind':kind, 'instrument':instrument,
            'required_command':row['requiredDance'] if dance else row['requiredSong'],
            'source_command':'startdance' if dance else 'startmusic', 'animation':animation,
            'performance_index':index, 'loop_seconds':row['loopDuration'],
            'action_per_loop':row['actionPointsPerLoop'], 'heal_shock':row['healShockWound'],
            'sounds':{k:row[k] for k in ['mainloop','intro','outro']+['flourish'+str(i) for i in range(1,9)] if row[k]}}
    effect_source='datatables/performance/perform_effect.iff'
    effect_raw=assets().read(effect_source)
    provenance[effect_source]=hashlib.sha256(effect_raw).hexdigest()
    names={'dazzle':'dazzle','distract':'distract','spotlight':'spot_light','colorlights':'color_lights','smokebomb':'smoke_bomb','firejets':'fire_jets','ventriloquism':'ventriloquism'}
    effects={}
    for row in datatable(effect_raw):
        family=row['effectName'][:-1].lower();level=int(row['effectName'][-1]);key=family+str(level)
        effects[key]={'command':'firejet' if family=='firejets' else family,'level':level,
            'effect_file':f'clienteffect/entertainer_{names[family]}_level_{level}.cef',
            'required_skill_mod_value':row['requiredSkillModValue'],
            'is_dance':'dance' in row['performanceType'],'is_music':'music' in row['performanceType'],
            'required_performing':bool(row['requiredPerforming']),'target_type':row['targetType'],
            'action_cost':row['effectActionCost'],'duration':row['effectDuration']}
    return {'schema':1, 'special_effects':effects, 'performances':performances, 'items':items, 'skill_grants':grants,
            'circle_radius':8.0, 'cull_distance':96.0, 'provenance':provenance}

def commands(learned):
    data = catalog()
    return {command.lower() for skill in learned for command in data['skill_grants'].get(skill, [])}

def eligible(learned, template):
    data = catalog()
    grant = commands(learned)
    item = data['items'].get(template.replace('/shared_', '/'), {})
    instrument = 'dance' if not template else item.get('instrument')
    if instrument != 'dance' and instrument not in grant: return []
    return [p for p in data['performances'].values() if p['instrument'] == instrument and p['required_command'].lower() in grant]

def context(result, oid):
    record = result.get('variables', {}).get('replication', {}).get('objects', {}).get('o'+str(oid), {})
    learned = skills(record)
    grant = commands(learned)
    return {'character_id':str(oid), 'skills':learned, 'commands':sorted(grant),
            'complete':bool(record.get('baseline1')), 'entertainer':'social_entertainer_novice' in learned,
            'flourishes':[i for i in range(1,9) if 'flourish+'+str(i) in grant]}
