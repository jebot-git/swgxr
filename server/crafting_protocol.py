"""Resolve the native crafting transaction; no local recipes or possessions."""
try:
 from .planets import SUPPORTED_PLANETS, context as planet_context, planet as validate_planet
except ImportError:
 from planets import SUPPORTED_PLANETS, context as planet_context, planet as validate_planet
from copy import deepcopy
from functools import lru_cache
import math, re, struct
try:
 from .character_protocol import assets, template_names, decode_customization
 from .datapad_protocol import display, template_label
except ImportError:
 from character_protocol import assets, template_names, decode_customization
 from datapad_protocol import display, template_label

# Original DraftSchematicObjectTemplate tool-tab flags / craft_types.stf.
CRAFT_CATEGORIES = {'1': 'weapon', '2': 'armor', '4': 'food', '8': 'clothing', '16': 'vehicle', '32': 'droid', '64': 'chemical', '128': 'plant_breeding', '256': 'animal_breeding', '512': 'furniture', '1024': 'installation', '2048': 'lightsaber', '4096': 'generic_item', '8192': 'genetics', '16384': 'mandalorian_tailor', '32768': 'mandalorian_armorsmith', '65536': 'mandalorian_droid_engineer', '131072': 'space', '262144': 'reverse_engineering', '524288': 'misc', '2148007936': 'mission'}

@lru_cache(maxsize=64)
def palette(path):
 if not isinstance(path,str) or not path.startswith('palette/') or '..' in path:raise ValueError('Invalid source palette')
 raw=assets().read(path)
 if raw[:4]!=b'RIFF':raise ValueError('Unsupported source palette')
 count=struct.unpack_from('<H',raw,22)[0]
 return [[r/255,g/255,b/255,a/255] for r,g,b,a in struct.iter_unpack('<4B',raw[24:24+4*count])]

def command(action,data):
 if action not in ('status','open','select','assemble','finish','cancel'):raise ValueError('Unsupported crafting action')
 out={'action':action,**planet_context(data)}
 if action!='status':
  key=data.get('request_id','')
  if not isinstance(key,str) or not re.fullmatch(r'[A-Za-z0-9_-]{8,64}',key):raise ValueError('Unique request_id required')
  out['request_id']=key
 if action not in ('status','cancel'):
  tool=data.get('tool_id')
  if not isinstance(tool,str) or not tool.isdigit() or not 0<int(tool)<2**64:raise ValueError('Owned tool_id required')
  p=data.get('position')
  if not isinstance(p,list) or len(p)!=3 or any(type(x) not in (int,float) or not math.isfinite(x) or abs(x)>(2048 if i==1 else 8192) for i,x in enumerate(p)):raise ValueError('Finite source position required')
  out.update(tool_id=tool,position=p)
  if 'building_id' in data:
   v=data['building_id'];ci=data.get('cell_index')
   if not isinstance(v,str) or not v.isdigit() or not 0<=int(v)<2**64 or type(ci) is not int or not 0<=ci<=256 or ((int(v)==0)!=(ci==0)):raise ValueError('Valid source building and cell required.')
   out.update(building_id=v,cell_index=ci)
 if action not in ('status','open'):
  sid=data.get('session_id','')
  if not isinstance(sid,str) or not re.fullmatch(r'[A-Za-z0-9_-]{8,64}',sid):raise ValueError('Crafting session_id required')
  out['session_id']=sid
 if action=='select':
  value=data.get('index')
  if type(value) is not int or not 0<=value<4096:raise ValueError('Invalid schematic index')
  out['index']=value
 if action=='assemble':
  allocations=data.get('allocations')
  if not isinstance(allocations,list) or len(allocations)>32 or any(not isinstance(s,list) or len(s)>64 or any(not isinstance(i,str) or not i.isdigit() or not 0<int(i)<2**64 for i in s) for s in allocations):raise ValueError('Invalid ingredient allocations')
  out['allocations']=allocations
 if action=='finish':
  output=data.get('output','prototype')
  if output not in ('prototype','blueprint'):raise ValueError('Invalid crafting output')
  out['output']=output
  if output=='blueprint':
   limit=data.get('manufacture_limit',1000)
   if type(limit) is not int or not 1<=limit<=1000:raise ValueError('Invalid manufacturing limit')
   out['manufacture_limit']=limit
  for field,maximum,count in [('points',10,32),('colors',255,32)]:
   values=data.get(field,[])
   if not isinstance(values,list) or len(values)>count or any(type(v) is not int or not 0<=v<=maximum for v in values):raise ValueError('Invalid '+field)
   out[field]=values
 return out

def crafting_snapshot(raw,oid):
 out=deepcopy(raw.get('variables',{}).get('crafting',{}))
 if out.get('character_id')!=str(oid):raise ValueError('Crafting response owner mismatch')
 if out.get('error'):raise ValueError(out['error'])
 state=out.get('state',{})
 if state.get('source_kind')!='core3_crafting' or state.get('character_id')!=str(oid):raise ValueError('Missing native crafting state')
 if len(state.get('inventory',[]))>256 or len(state.get('schematics',[]))>4096 or len(state.get('jobs',[]))>80:raise ValueError('Crafting snapshot exceeds bounds')
 def label(row):
  row['name']=row.get('custom_name') or display(row.get('name_table',''),row.get('name_key',''),row.get('name') or template_label(row.get('template',''))[0])
  category=CRAFT_CATEGORIES.get(str(row.get('category_id','')))
  if category:row['category']=display('craft_types',category,category.replace('_',' ').title())
  description=row.get('description','')
  if description.startswith('@') and ':' in description:
   table,key=description[1:].split(':',1);row['description']=display(table,key,description)
  for slot in row.get('slots',[]):
   if isinstance(slot,dict):slot['name']=display(slot.get('name_table',''),slot.get('name_key',''),slot.get('type','Ingredient'))
 for row in state.get('schematics',[]):label(row)
 if state.get('schematic'):label(state['schematic'])
 names=template_names()
 for item in state.get('inventory',[]):
  label(item);item['shared_template']=names.get(item.get('client_crc'),'');item['customization']=decode_customization(bytes.fromhex(item.get('customization_hex','')))
 for color in state.get('colors',[]):
  color['colors']=palette(color['palette']);color['maximum']=min(color['maximum'],len(color['colors'])-1)
 out['backend']='core3';out['source_kind']='core3_crafting'
 return out
