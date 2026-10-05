"""Decode actual Core3 baseline state and SWG customization bytes.

Layout references are the pinned Core3 TangibleObjectMessage3,
CreatureObjectMessage1/3, and CustomizationVariables implementation.
"""
from __future__ import annotations
import json
from pathlib import Path
import re
import struct
import sys
from functools import lru_cache

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools/assets'))
from swg_formats import TreSet, parse_iff, cstring

SPECIES_LABELS = {'human':'Human','rodian':'Rodian','trandoshan':'Trandoshan',
                  'moncal':'Mon Calamari','wookiee':'Wookiee','bothan':'Bothan',
                  'twilek':"Twi’lek",'zabrak':'Zabrak','ithorian':'Ithorian','sullustan':'Sullustan'}
PROFESSION_LABELS = {'crafting_artisan':'Artisan','combat_brawler':'Brawler',
                     'social_entertainer':'Entertainer','combat_marksman':'Marksman',
                     'science_medic':'Medic','outdoors_scout':'Scout'}

def crc(value):
    result = 0xffffffff
    for byte in value.encode('ascii'):
        result = ((result << 8) ^ CRC_TABLE[((result >> 24) ^ byte) & 255]) & 0xffffffff
    return result ^ 0xffffffff

def crc_table():
    result=[]
    for n in range(256):
        n <<= 24
        for _ in range(8):
            n = ((n << 1) ^ (0x04c11db7 if n & 0x80000000 else 0)) & 0xffffffff
        result.append(n)
    return result
CRC_TABLE = crc_table()

@lru_cache(maxsize=1)
def assets():
    return TreSet(ROOT / 'runtime/assets/active_tre')

@lru_cache(maxsize=1)
def template_names():
    result = {crc(p):p for p in assets().entries if p.startswith('object/') and p.endswith('.iff')}
    # Login enumeration uses server template CRCs; scene replication uses shared ones.
    result.update({crc(p.replace('/shared_', '/')):p.replace('/shared_', '/')
                   for p in list(result.values()) if '/shared_' in p})
    return result

@lru_cache(maxsize=1)
def customization_ids():
    data=parse_iff(assets().read('customization/customization_id_manager.iff')).first('DATA').data
    result={}; pos=0
    while pos<len(data):
        idx=struct.unpack_from('<H',data,pos)[0]
        name,pos=cstring(data,pos+2)
        result[name]=idx
    return result

def decode_customization(data):
    if not data: return {}
    pos=0
    def take():
        nonlocal pos
        v=data[pos];pos+=1
        if v==255:
            escape=data[pos];pos+=1
            if escape not in (1,2): raise ValueError('Invalid customization escape.')
            v=0 if escape==1 else 255
        return v
    if take()!=1: raise ValueError('Unsupported customization version.')
    count=take(); result={}; reverse={v:k for k,v in customization_ids().items()}
    for _ in range(count):
        idx=take();value=take()
        if idx&128:
            idx &= 127; value |= take()<<8
            if value&0x8000: value-=65536
        result[reverse.get(idx,f'unknown_id_{idx}')]=value
    if data[pos:] != b'\xff\x03': raise ValueError('Invalid customization terminator.')
    return result

def encode_customization(values):
    if not values:return ''
    ids=customization_ids();out=bytearray([1,len(values)])
    def push(v):
        out.extend(b'\xff\x01' if v==0 else b'\xff\x02' if v==255 else bytes([v]))
    for name,value in sorted(values.items(),key=lambda item:ids[item[0]]):
        idx=ids[name]
        if not 0<idx<128 or not -256<=value<=255:raise ValueError('Customization value is not representable.')
        push(idx | (128 if value<0 else 0)); push(value&255)
        if value<0:push(255)
    out.extend(b'\xff\x03');return out.hex()

class Reader:
    def __init__(self,data):self.data=data;self.pos=0
    def take(self,n):
        if n<0 or self.pos+n>len(self.data):raise ValueError('Truncated Core3 appearance baseline.')
        v=self.data[self.pos:self.pos+n];self.pos+=n;return v
    def number(self,fmt):return struct.unpack('<'+fmt,self.take(struct.calcsize('<'+fmt)))[0]
    def u32(self):return self.number('I')
    def u64(self):return self.number('Q')
    def ascii(self):return self.take(self.number('H'))
    def unicode(self):return self.take(self.u32()*2).decode('utf-16-le')
    def vector(self,width):
        count=self.u32();self.u32();return self.take(count*width)

def tangible(record):
    r=Reader(bytes.fromhex(record['baseline3']))
    complexity=r.number('f');stf=r.ascii().decode('ascii');r.u32();key=r.ascii().decode('ascii')
    name=r.unicode();r.u32();custom=r.ascii()
    r.vector(4);r.u32();r.u32();r.u32();r.u32();r.take(1)
    out={'name':name,'name_string_id':{'table':stf,'key':key},
         'customization':decode_customization(custom),'customization_hex':custom.hex()}
    if record.get('type')==0x4352454f:
        r.take(2);r.u64();out['height']=r.number('f')
    return out

def skills(record):
    if not record.get('baseline1'):return []
    r=Reader(bytes.fromhex(record['baseline1']));r.take(8);r.vector(4)
    count=r.u32();r.u32()
    return [r.ascii().decode('ascii') for _ in range(count)]

def race_from_template(template):
    stem=Path(template).stem.removeprefix('shared_')
    if '_' not in stem:return '', '', ''
    species,sex=stem.rsplit('_',1)
    return species,sex,stem

def summarize(entry):
    template=template_names().get(entry.get('templateCrc'), '')
    species,sex,race=race_from_template(template)
    return {'id':str(entry['oid']),'name':entry['name'],'species':species,'sex':sex,
            'race':race,'template':template,'galaxy_id':entry['galaxyId']}

def appearance(result,oid):
    objects=result.get('variables',{}).get('replication',{}).get('objects',{})
    player=objects.get('o'+str(oid))
    if not player or not player.get('baseline3'):
        raise ValueError('Core3 did not replicate the selected player appearance.')
    names=template_names();body=tangible(player)
    scene=result['variables']['scene'];template=scene['race']
    species,sex,race=race_from_template(template)
    learned=skills(player)
    professions=[p for p in PROFESSION_LABELS if p+'_novice' in learned]
    equipment=[];hair=None
    for key,record in objects.items():
        if record.get('parentId')!=str(oid) or not record.get('baseline3'):continue
        item_template=names.get(record.get('templateCrc'),'')
        if not item_template.startswith(('object/tangible/hair/','object/tangible/wearables/','object/weapon/')):continue
        item=tangible(record)
        item.update(id=key.removeprefix('o'),template=item_template,template_crc=record.get('templateCrc'),
                    containment_type=record.get('containmentType'))
        if item_template.startswith('object/tangible/hair/'):hair=item
        else:equipment.append(item)
    avatar={'race':race,'template':template,'species':species,'sex':sex,
            'height':body.get('height',1.0),'customization':body['customization'],
            'customization_hex':body['customization_hex'],'hair':hair,'equipment':equipment,
            'source':'core3_replication'}
    return {'id':str(oid),'name':body['name'],'species':species,'sex':sex,'race':race,
            'template':template,'profession':professions[0] if len(professions)==1 else None,
            'professions':professions,'profession_source':'core3_skills','skills':learned,
            'biography':result.get('variables',{}).get('appearance',{}).get('biography'),
            'appearance':avatar,'equipment':equipment}
