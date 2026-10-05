"""Original-media character options and strict protocol input validation."""
import json, math, re, struct
from functools import lru_cache
try:
    from .character_protocol import ROOT, assets, crc, customization_ids, encode_customization, SPECIES_LABELS, PROFESSION_LABELS, parse_iff, cstring
except ImportError:
    from character_protocol import ROOT, assets, crc, customization_ids, encode_customization, SPECIES_LABELS, PROFESSION_LABELS, parse_iff, cstring
from character_formats import datatable

@lru_cache(maxsize=1)
def registry():
    root=parse_iff(assets().read('customization/asset_customization_manager.iff'))
    return {n.tag:n.data for n in root.walk() if n.data}

@lru_cache(maxsize=256)
def appearance_controls(appearance):
    t=registry(); result={};visited=set()
    cidx=dict(struct.iter_unpack('<IH',t['CIDX']))
    uidx={k:(start,count) for k,start,count in struct.iter_unpack('<HHB',t['UIDX'])}
    lidx={k:(start,count) for k,start,count in struct.iter_unpack('<HHB',t['LIDX'])}
    def integer(table,index,fmt='H'):
        return struct.unpack_from('<'+fmt,t[table],struct.calcsize('<'+fmt)*index)[0]
    def string(table,index):return cstring(t['NAME'],integer(table,index-1))[0]
    def visit(key):
        if key in visited:return
        visited.add(key)
        start,count=uidx.get(key,(0,0))
        for i in range(start,start+count):
            idx=integer('ULST',i)-1
            nameidx,typeidx,defaultidx=struct.unpack_from('<BBB',t['UCMP'],idx*3)
            name=string('VNOF',nameidx)
            if name in result:continue
            typ=integer('RTYP',typeidx-1);default=integer('DEFV',defaultidx-1,'i')
            desc={'id':name,'label':name.rsplit('/',1)[-1].replace('blend_','').replace('index_color_','').replace('_',' ').title(),'default':default,'source':'asset_customization_manager.iff'}
            if typ&0x8000:
                palette=string('PNOF',typ&0x7fff);raw=assets().read(palette)
                if raw[:4]!=b'RIFF':raise ValueError('Unsupported palette format.')
                count=struct.unpack_from('<H',raw,22)[0]
                desc.update(type='color',min=0,max=count-1,palette=palette,
                            colors=[[r/255,g/255,b/255,a/255] for r,g,b,a in struct.iter_unpack('<4B',raw[24:24+4*count])])
            else:
                low,high=struct.unpack_from('<ii',t['IRNG'],(typ-1)*8)
                desc.update(type='int',min=low,max=high-1)
            if name in customization_ids():result[name]=desc
        start,count=lidx.get(key,(0,0))
        for i in range(start,start+count):visit(integer('LLST',i))
    if crc(appearance) not in cidx:raise ValueError('Appearance absent from original customization registry: '+appearance)
    visit(cidx[crc(appearance)])
    return list(result.values())

@lru_cache(maxsize=1)
def hair_rules():
    return datatable(assets().read('datatables/customization/hair_assets_skill_mods.iff'))

@lru_cache(maxsize=1)
def bald_rules():
    return {r['SPECIES_GENDER']:bool(r['ALLOW_BALD']) for r in datatable(assets().read('datatables/customization/allow_bald.iff'))}

@lru_cache(maxsize=1)
def palette_creation_limits():
    return {r['PALETTE']:r for r in datatable(assets().read('datatables/customization/palette_columns.iff'))}

def creation_controls(appearance):
    controls=[dict(c) for c in appearance_controls(appearance)]
    for c in controls:
        if c['type']!='color':continue
        rule=palette_creation_limits().get(c['palette'].rsplit('/',1)[-1].split('.')[0])
        if rule:
            c['palette_max']=c['max'];c['max']=min(c['max'],rule['CREATION_INDEXES']-1)
            c['creation_columns']=rule['CREATION_COLUMNS']
            c['colors']=c['colors'][:c['max']+1]
            c['source']+=' + palette_columns.iff creation limits'
    return controls

def creation_options():
    catalog=json.loads((ROOT/'runtime/assets/characters/catalog.json').read_text())
    races={}
    for race,raw in catalog['races'].items():
        controls=creation_controls(raw['appearance'])
        original=raw.get('customizations',[])
        for control in controls:
            variable=control['id'].rsplit('/',1)[-1]
            original_control=next((c for c in original if variable in c['variables']),{})
            control['group']=original_control.get('group','appearance')
            control['preview_supported']=original_control.get('supported',False)
        hair=[]
        allowed={r['SERVER_TEMPLATE'] for r in hair_rules() if r['SERVER_PLAYER_TEMPLATE']==raw['template'] and r['AVAILABLE_AT_CREATION']}
        for h in raw.get('hair',[]):
            if h['template'] not in allowed:continue
            h=dict(h);h.update(id=h['template'],label='Style '+str(len(hair)+1),appearance_controls=creation_controls(h['appearance']))
            hair.append(h)
        races[race]={'template':raw['template'],'shared_template':raw['shared_template'],
            'appearance_controls':controls,'original_controls':original,'hair':hair,
            'allow_bald':bald_rules().get(race,True),
            'allow_bald_source':'allow_bald.iff' if race in bald_rules() else 'no_rule_in_original_table',
            'height':{'min':raw['height_min'],'max':raw['height_max'],
                      'default':(raw['height_min']+raw['height_max'])/2,
                      'default_source':'midpoint_of_original_template_range'},
            'default_hair':raw.get('default_hair','').replace('/shared_','/') or (hair[0]['template'] if hair and not bald_rules().get(race,True) else '')}
    professions=[]
    for node in parse_iff(assets().read('creation/profession_defaults.iff')).walk('DATA'):
        name,pos=cstring(node.data)
        if name in PROFESSION_LABELS:professions.append({'id':name,'label':PROFESSION_LABELS[name]})
    return {'species':[{'id':s,'label':label,'sexes':[{'id':sex,'label':sex.title()} for sex in ('male','female') if s+'_'+sex in races]} for s,label in SPECIES_LABELS.items() if any(s+'_'+sex in races for sex in ('male','female'))],
            'professions':professions,'races':races,'source':'user_media_precu_14_1',
            'customization_source':'ACST IRNG/DEFV, original PAL and CIDM tables'}

def values(body,key,controls):
    submitted=body.get(key,{})
    if not isinstance(submitted,dict):raise ValueError(key+' must be an object.')
    allowed={c['id']:c for c in controls};result={}
    for name,value in submitted.items():
        if name not in allowed:raise ValueError('Unknown '+key+' variable: '+name)
        rule=allowed[name]
        if isinstance(value,bool) or not isinstance(value,(int,float)) or not math.isfinite(value) or int(value)!=value or not rule['min']<=value<=rule['max']:
            raise ValueError(f'{name} must be an integer in [{rule["min"]}, {rule["max"]}].')
        result[name]=int(value)
    return result

def creation_action(data):
    options=creation_options();species=data.get('species','human');sex=data.get('sex','male')
    if isinstance(species,str) and species.endswith(('_male','_female')):species,sex=species.rsplit('_',1)
    race=str(species)+'_'+str(sex)
    if race not in options['races']:raise ValueError('Choose an available original species and sex.')
    entry=options['races'][race];name=data.get('name','')
    if not isinstance(name,str) or not re.fullmatch(r"[A-Za-z][A-Za-z'-]{1,24}( [A-Za-z][A-Za-z'-]{0,24})?",name):
        raise ValueError('Use a first name and optional surname containing letters, apostrophes or hyphens; Core3 applies its species naming rules.')
    profession=data.get('profession','crafting_artisan')
    if profession not in {p['id'] for p in options['professions']}:raise ValueError('Choose one of the six original starting professions.')
    bounds=entry['height'];height=data.get('height',bounds['default'])
    if isinstance(height,bool) or not isinstance(height,(int,float)) or not math.isfinite(height) or not bounds['min']-1e-6<=height<=bounds['max']+1e-6:
        raise ValueError(f'Height must be in [{bounds["min"]}, {bounds["max"]}].')
    # Godot JSON decimal formatting can round the original float32 endpoints.
    # Tolerate only serialization noise, then send the exact legal bounds.
    height=min(bounds['max'],max(bounds['min'],height))
    biography=data.get('biography','')
    if not isinstance(biography,str) or len(biography)>4096 or '\0' in biography:raise ValueError('Biography must contain at most 4096 characters and no NUL.')
    body=values(data,'customization',entry['appearance_controls'])
    hair_template=data.get('hair_template',entry['default_hair'] if not entry['allow_bald'] else '')
    hair=next((h for h in entry['hair'] if h['template']==hair_template),None)
    if hair_template and hair is None:raise ValueError('Hair style is not available at creation for this race.')
    if not hair_template and not entry['allow_bald']:raise ValueError('This race requires a hair style.')
    hair_values=values(data,'hair_customization',hair['appearance_controls'] if hair else [])
    return {'action':'createCharacter','name':name,'race':entry['template'],'profession':profession,
            'height':height,'biography':biography,'hairTemplate':hair_template,
            'customizationHex':encode_customization(body),'hairCustomizationHex':encode_customization(hair_values),
            'skipTutorial':True}
