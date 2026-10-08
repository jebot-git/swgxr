"""Shared, bounded client release format; mirrored into the launcher bootstrap."""
import hashlib
import json
import re

PLATFORMS={'linux-x86_64':'engine/godot', 'windows-x86_64':'engine/godot.exe'}
SCHEMA=1
CHUNK_SIZE=4*1024*1024
MAX_MANIFEST=32*1024*1024
MAX_FILES=100000
MAX_TOTAL=128*1024**3
ROOT_TOKEN=b'@@SWGXR_ROOT@@'

def digest(data):return hashlib.sha256(data).hexdigest()

def encode(value):return json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=True).encode()

def unique(pairs):
    out={}
    for key,value in pairs:
        if key in out:raise ValueError('Duplicate JSON field')
        out[key]=value
    return out

def decode(raw):return json.loads(raw,object_pairs_hook=unique,parse_constant=lambda _: (_ for _ in ()).throw(ValueError('Invalid JSON constant')))

def sha(value):
    if not isinstance(value,str) or not re.fullmatch('[0-9a-f]{64}',value):raise ValueError('Invalid content hash')
    return value

def channel_name(value):
    if not isinstance(value,str) or not re.fullmatch('[a-z][a-z0-9-]{0,63}',value):raise ValueError('Invalid release channel')
    return value

def safe_path(value):
    if not isinstance(value,str) or len(value)>240 or not value.isascii():raise ValueError('Invalid client path')
    parts=value.split('/')
    for part in parts:
        if not part or part in ('.','..') or part.endswith(('.', ' ')) or not re.fullmatch('[A-Za-z0-9_.@+ -]+',part):raise ValueError('Invalid client path')
        if part.split('.')[0].upper() in {'CON','PRN','AUX','NUL',*(f'COM{i}' for i in range(10)),*(f'LPT{i}' for i in range(10))}:raise ValueError('Reserved client path')
    if parts[0] not in ('client','engine','runtime') or (parts[0]=='runtime' and not (parts[1:2]==['assets'] or value=='runtime/combat/catalog.json' or parts[1:3] in (['combat','abilities'],['combat','player_postures']) or parts[1:2]==['entertainment'])):raise ValueError('Client path outside managed payload')
    return value

def manifest(value,channel=None,platform=None):
    if not isinstance(value,dict) or value.get('schema')!=SCHEMA or value.get('platform') not in PLATFORMS:raise ValueError('Unsupported client release')
    if platform is not None and value['platform']!=platform:raise ValueError('Release platform mismatch')
    engine=PLATFORMS[value['platform']]
    actual=channel_name(value.get('channel'))
    if channel is not None and actual!=channel:raise ValueError('Release channel mismatch')
    if type(value.get('sequence')) is not int or value['sequence']<1:raise ValueError('Invalid release sequence')
    if not isinstance(value.get('version'),str) or not re.fullmatch('[A-Za-z0-9._-]{1,64}',value['version']):raise ValueError('Invalid release version')
    rows=value.get('files')
    if not isinstance(rows,list) or not 1<=len(rows)<=MAX_FILES:raise ValueError('Invalid release file count')
    names=set();total=0
    for row in rows:
        if not isinstance(row,dict):raise ValueError('Invalid release file')
        name=safe_path(row.get('path'));key=name.casefold()
        if key in names:raise ValueError('Duplicate or case-colliding client path')
        names.add(key);sha(row.get('sha256'))
        size=row.get('size');chunks=row.get('chunks')
        if type(size) is not int or not 0<=size<=MAX_TOTAL:raise ValueError('Invalid file size')
        if type(row.get('executable')) is not bool or type(row.get('relocate')) is not bool:raise ValueError('Invalid file attributes')
        if row['relocate'] and not name.endswith('.json'):raise ValueError('Only JSON data paths can be relocated')
        if not isinstance(chunks,list) or len(chunks)!=(size+CHUNK_SIZE-1)//CHUNK_SIZE:raise ValueError('Invalid chunk count')
        for chunk in chunks:sha(chunk)
        total+=size
    for name in names:
        parts=name.split('/')
        if any('/'.join(parts[:n]) in names for n in range(1,len(parts))):raise ValueError('File/directory collision')
    if total>MAX_TOTAL or value.get('total_bytes')!=total:raise ValueError('Invalid release size')
    if not {engine,'client/project.godot'}<={r['path'] for r in rows}:raise ValueError('Client runtime or project missing')
    if not next(r for r in rows if r['path']==engine)['executable']:raise ValueError('Client runtime must be executable')
    return value
