"""Recipient-private original NPC speech; presentation never grants native skills."""
from functools import lru_cache
from pathlib import Path
import json,math,os,re
try:
 from .datapad_protocol import display
except ImportError:
 from datapad_protocol import display
ROOT=Path(__file__).resolve().parents[1]
@lru_cache(maxsize=1)
def catalog():
 path=Path(os.environ.get('SWGXR_CHATTER_CATALOG_PATH',str(ROOT/'runtime/assets/chatter/catalog.json')))
 try:
  data=json.loads(path.read_text());return {r['id']:r for r in data['languages']if type(r.get('id'))is int}
 except (OSError,ValueError,KeyError,TypeError):return {}

def source_text(value):
 if not isinstance(value,str):return ''
 if value.startswith('@')and ':'in value:
  table,key=value[1:].split(':',1);return display(table,key,'')
 return value

def parameter(value,names):
 if not isinstance(value,dict):return source_text(value)
 if value.get('customName'):return source_text(value['customName'])
 pointer=value.get('pointerParameter',0)
 if pointer:return names.get(str(pointer),'')
 sid=value.get('stringID',{})
 if isinstance(sid,dict):return display(sid.get('file',''),sid.get('stringID',''),'')
 return source_text(sid)

def message_text(value,names):
 if not isinstance(value,dict):return ''
 if 'text'in value:text=source_text(value['text'])
 else:text=display(value.get('file',''),value.get('stringID',''),'')
 for key in ('TT','TU','TO'):text=text.replace('%'+key,parameter(value.get(key,{}),names))
 for key in ('DI','DF'):
  number=value.get(key,0)
  if type(number)in(int,float)and math.isfinite(number):text=text.replace('%'+key,str(number))
 # Native chat formatting has no authority over Godot markup or layout.
 return re.sub(r'\\#[0-9a-fA-F]{6}|\\#\.','',text).replace('\x00','')[:2048]

def scramble(text,language):
 # NGE convertToLanguage case behavior, using the actual table's i column
 # instead of that source client's duplicated-h installation typo.
 syllables=language.get('syllables',{})
 return ''.join((syllables.get(ch.lower())or ch).upper()if 'A'<=ch<='Z'else (syllables.get(ch)or ch)if 'a'<=ch<='z'else ch for ch in text)[:2048]

def normalize(value,player=None,world=None):
 if not isinstance(value,dict):return {'sequence':0,'events':[],'languages':[]}
 player=player or {};world=world or {};languages=catalog();names={str(player.get('id','')):source_text(player.get('name',''))}
 for row in world.get('players',[])+world.get('actors',[]):names[str(row.get('id',''))]=source_text(row.get('name',''))
 out={'sequence':value.get('sequence',0),'events':[],'languages':[]}
 for row in value.get('languages',[])[:32]:
  if not isinstance(row,dict)or row.get('id')not in languages:continue
  out['languages'].append(dict(row,name=languages[row['id']].get('name',row.get('key',''))))
 seen=set()
 for row in value.get('events',[])[:32]:
  if not isinstance(row,dict):continue
  identifier=row.get('id');language=languages.get(row.get('language_id'));age=row.get('age_ms');position=row.get('position')
  if not isinstance(identifier,str)or not identifier.isascii()or not identifier.isdigit()or identifier in seen or not language or type(age)not in(int,float)or not 0<=age<6000:continue
  if not isinstance(position,list)or len(position)!=3 or any(type(v)not in(int,float)or not math.isfinite(v)for v in position):continue
  before=row.get('comprehension_before',0);after=row.get('comprehension_after',0)
  if any(type(v)not in(int,float)or not math.isfinite(v)or not 0<=v<=100 for v in (before,after)):continue
  text=message_text(row['message'],names)if 'message'in row else row.get('text','')
  if not text:continue
  if after<100 and not language.get('audible',False):text='[Unfamiliar body language]'
  elif 'message'in row and after<100:text=scramble(text,language)
  clean={k:row[k]for k in ('id','actor_id','position','zone','building_id','cell_index','language_id','language_key','comprehension_before','comprehension_after','age_ms')if k in row}
  clean.update(name=source_text(row.get('name','')),text=text,language_name=language.get('name',row.get('language_key','')),lifetime_ms=6000,age_ms=int(age),understood=after>=100)
  out['events'].append(clean);seen.add(identifier)
 return out
