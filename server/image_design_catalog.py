"""Skill-gated original image designer controls and matching preview conversion."""
import copy
import json
import math
from functools import lru_cache
try:
    from .character_protocol import ROOT, assets
    from .creation_catalog import appearance_controls, hair_rules, bald_rules, palette_creation_limits
except ImportError:
    from character_protocol import ROOT, assets
    from creation_catalog import appearance_controls, hair_rules, bald_rules, palette_creation_limits
from character_formats import datatable

@lru_cache(maxsize=1)
def definitions():
    return (datatable(assets().read('datatables/customization/customization_data.iff')),
            datatable(assets().read('datatables/customization/holoemotes.iff')),
            json.loads((ROOT/'runtime/assets/characters/catalog.json').read_text()))

def options(designer, appearance):
    rows, holo, characters = definitions()
    race=appearance['race']; source=characters['races'][race]
    mods=designer.get('skill_mods',{}); learned=designer.get('skills',[])
    hair=[h for h in source.get('hair',[]) if any(r['SERVER_TEMPLATE']==h['template'] and r['SERVER_PLAYER_TEMPLATE']==source['template'] and r['SKILL_MOD_VALUE']<=mods.get('hair',0) for r in hair_rules())]
    controls=[]
    body_vars=appearance_controls(source['appearance'])
    hair_vars={h['template']:appearance_controls(h['appearance']) for h in hair}
    for row in rows:
        if row['SPECIES_GENDER']!=race or mods.get(row['IMAGEDESIGN_SKILLMOD'],0)<row['SKILLMOD_VALUE']: continue
        if row['TYPE'] not in ('hslider','vslider','color'): continue
        scope='hair' if row['IS_VAR_HAIR_COLOR'] else 'body'
        variables=list(filter(None,row['VARIABLES'].split(',')))
        candidates=body_vars if scope=='body' else [c for v in hair_vars.values() for c in v]
        matched=[c for var in variables for c in candidates if c['id'].rsplit('/',1)[-1]==var]
        if not matched and not row['IS_SCALE']: continue
        color=row['TYPE']=='color'
        maximum=min(255,min(c['max'] for c in matched)) if color else 1.0
        if color:
            skill=row['IMAGEDESIGN_SKILLMOD']
            branch={'body':'bodyform','face':'exotic','hair':'hairstyle'}.get(skill,skill)
            tier=max([0]+[i for i in range(1,5) if f'social_imagedesigner_{branch}_0{i}' in learned])
            column='ID_MASTER_INDEXES' if 'social_imagedesigner_master' in learned else f'ID_LEVEL{tier}_INDEXES' if tier else 'ID_NOVICE_INDEXES'
            for c in matched:
                rule=palette_creation_limits().get(c.get('palette','').rsplit('/',1)[-1].split('.')[0],{})
                maximum=min(maximum,rule.get(column,256)-1)
        controls.append({'id':row['CUSTOMIZATION_NAME'],'label':row['CUSTOMIZATION_NAME'].replace('_',' ').title(),
            'type':'color' if color else 'shape','scope':scope,'min':0,'max':maximum,'step':1 if color else 0.01,
            'variables':variables,'reverse':bool(row['REVERSE']),'height':bool(row['IS_SCALE']),
            'colors':matched[0].get('colors',[])[:int(maximum)+1] if color and matched else []})
    # Project the recipient's current source customization into each UI control.
    # An untouched control must not silently start from an arbitrary midpoint.
    existing_hair=(appearance.get('hair') or {})
    existing_template=existing_hair.get('template','').replace('/shared_','/')
    current_hair_vars=hair_vars.get(existing_template,[])
    for control in controls:
        if control['height']:
            span=source['height_max']-source['height_min']
            value=(appearance.get('height',1.0)-source['height_min'])/span if span else .5
        else:
            source_vars=body_vars if control['scope']=='body' else current_hair_vars
            customization=appearance.get('customization',{}) if control['scope']=='body' else existing_hair.get('customization',{})
            components=[]
            for name in control['variables']:
                var=next((v for v in source_vars if v['id'].rsplit('/',1)[-1]==name),None)
                if var is None:components.append(0.0);continue
                raw=customization.get(var['id'],var.get('default',0))
                if control['type']=='color':components.append(raw);continue
                span=var['max']-var['min']
                components.append(((var['max']-raw) if control['reverse'] else (raw-var['min']))/span if span else 0)
            value=(.5+(components[1]-components[0])*.5) if len(components)==2 and control['type']!='color' else components[0] if components else 0
        control['value']=max(control['min'],min(control['max'],value))
    return {'race':race,'controls':controls,'hair':[{'template':h['template'],'label':'Style '+str(i+1)} for i,h in enumerate(hair)],
            'allow_bald':bald_rules().get(race,True), 'holoemotes':[r['HOLOEMOTE'] for r in holo if mods.get('hair',0)>=r['REQUIRED_HAIR_SKILLMOD']],
            'source':'original_image_design_tables'}

def proposal(designer, original, draft):
    available=options(designer,original)
    if not isinstance(draft,dict): raise ValueError('Invalid design draft.')
    attributes=draft.get('attributes',{})
    if not isinstance(attributes,dict) or len(attributes)>128: raise ValueError('Invalid design attributes.')
    price=draft.get('price',0)
    if type(price)!=int or not 0<=price<=10000: raise ValueError('Price must be an integer from 0 to 10000.')
    hair=draft.get('hair_template',original.get('hair',{}).get('template','') if original.get('hair') else '').replace('/shared_','/')
    existing=(original.get('hair') or {}).get('template','').replace('/shared_','/')
    if hair!=existing and hair not in {h['template'] for h in available['hair']} and (hair or not available['allow_bald']):
        raise ValueError('Hair style has not been learned for this species.')
    holo=draft.get('holoemote','')
    if holo and holo not in available['holoemotes']: raise ValueError('Holoemote has not been learned.')
    preview=copy.deepcopy(original)
    preview['hair']={'template':hair,'customization':copy.deepcopy((original.get('hair') or {}).get('customization',{}))} if hair else None
    rows,_,characters=definitions(); source=characters['races'][original['race']]
    body_vars=appearance_controls(source['appearance'])
    hair_source=next((h for h in source.get('hair',[]) if h['template']==hair),None)
    hair_vars=appearance_controls(hair_source['appearance']) if hair_source else []
    normalized={}; colors={}
    by_id={c['id']:c for c in available['controls']}
    for name,value in attributes.items():
        rule=by_id.get(name)
        if not rule or type(value) not in (int,float) or not math.isfinite(value) or not rule['min']<=value<=rule['max'] or (rule['type']=='color' and int(value)!=value):
            raise ValueError('Unlearned or out-of-range image design control: '+name)
        (colors if rule['type']=='color' else normalized)[name]=value
        if rule['height']:
            preview['height']=source['height_min']+value*(source['height_max']-source['height_min'])
            continue
        target=preview['customization'] if rule['scope']=='body' else preview['hair']['customization'] if preview['hair'] else None
        if target is None: continue
        variables=body_vars if rule['scope']=='body' else hair_vars
        for index,var in enumerate(rule['variables']):
            limit=next((c for c in variables if c['id'].rsplit('/',1)[-1]==var),None)
            if not limit: continue
            amount=max(0,(value-0.5)*2*(-1+index*2)) if len(rule['variables'])==2 and rule['type']!='color' else value
            mapped=int(limit['max']-amount*(limit['max']-limit['min']) if rule['reverse'] else limit['min']+amount*(limit['max']-limit['min'])) if rule['type']!='color' else int(value)
            target[limit['id']]=mapped
    return {'price':price,'attributes':attributes,'body':normalized,'colors':colors,'hair_template':hair,
            'hair_changed':hair!=existing,'holoemote':holo,'preview':preview,'options':available}
