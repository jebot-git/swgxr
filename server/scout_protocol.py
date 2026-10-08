"""Validated native scout actions; no local rewards, buffs or camp authority."""
try:
 from .planets import SUPPORTED_PLANETS, context as planet_context, planet as validate_planet
except ImportError:
 from planets import SUPPORTED_PLANETS, context as planet_context, planet as validate_planet
from copy import deepcopy
import math,re
try:
 from .inventory_protocol import inventory_snapshot
 from .character_protocol import decode_customization
 from .datapad_protocol import display,template_label
except ImportError:
 from inventory_protocol import inventory_snapshot
 from character_protocol import decode_customization
 from datapad_protocol import display,template_label
ACTIONS=('inspect','holster','return_tool','status','forage','trap','camp','disband','mask_scent','discard_mask_scent','burst_run','sample_dna','discard_sample_dna','ranger_status','conceal','rescue','area_track')
def command(action,data):
 if action not in ACTIONS:raise ValueError('Unsupported scout action')
 p=data.get('position')
 if not isinstance(p,list) or len(p)!=3 or any(type(v) not in (int,float) or not math.isfinite(v) or abs(v)>(2048 if i==1 else 8192) for i,v in enumerate(p)):raise ValueError('Finite source position required')
 out={'action':action,'position':p,**planet_context(data)}
 if action in ('ranger_status','conceal','rescue','area_track'):
  building=data.get('building_id','0');cell=data.get('cell_index',0)
  if not isinstance(building,str) or not building.isascii() or not building.isdigit() or not 0<=int(building)<2**64 or type(cell)is not int or not 0<=cell<=255 or (int(building)==0)!=(cell==0):raise ValueError('Invalid native cell context')
  out.update(building_id=building,cell_index=cell)
 if 'posture' in data:
  if data['posture'] not in ('standing','kneeling','prone'):raise ValueError('Invalid tracked posture')
  out['posture']=data['posture']
 if action not in ('status','ranger_status','inspect'):
  key=data.get('request_id','')
  if not isinstance(key,str) or not re.fullmatch(r'[A-Za-z0-9_-]{8,64}',key):raise ValueError('Unique scout request_id required')
  out['request_id']=key
 for field in {'inspect':('target_id',),'holster':('item_id',),'return_tool':('item_id',),'trap':('item_id','target_id'),'camp':('item_id',),'disband':('terminal_id',),'sample_dna':('target_id',),'conceal':('item_id',),'rescue':('target_id',)}.get(action,()):
  value=data.get(field)
  if not isinstance(value,str) or not value.isascii() or not value.isdigit() or not 0<int(value)<2**64:raise ValueError('Invalid '+field)
  out[field]=value
 if action=='conceal' and data.get('target_id') is not None:
  value=data['target_id']
  if not isinstance(value,str) or not value.isascii() or not value.isdigit() or not 0<int(value)<2**64:raise ValueError('Invalid target_id')
  out['target_id']=value
 if action=='area_track':
  kind=data.get('track_type','animal')
  if kind not in ('animal','npc','player'):raise ValueError('Invalid tracking type')
  out['track_type']=kind
 if action=='sample_dna' or (action=='conceal' and out.get('target_id')):
  hand=data.get('hand_position')
  if not isinstance(hand,list) or len(hand)!=3 or any(type(v) not in (int,float) or not math.isfinite(v) or abs(v)>10000 for v in hand):raise ValueError('Finite tracked hand_position required')
  if sum((a-b)**2 for a,b in zip(hand,p))>3.5**2:raise ValueError('Tracked hand outside physical reach')
  out['hand_position']=hand
 return out

def snapshot(raw,oid,attributes=None):
 out=deepcopy(raw)
 if out.get('error'):raise ValueError(out['error'])
 if out.get('character_id')!=str(oid) or out.get('source_kind')!='core3_scout':raise ValueError('Missing owned native scout response')
 state=out.get('state',{})
 if state.get('character_id')!=str(oid) or len(state.get('targets',[]))>96 or len(state.get('camps',[]))>16:raise ValueError('Invalid scout snapshot bounds')
 ranger=state.get('ranger',{})
 if len(ranger.get('targets',[]))>64 or len(ranger.get('kits',[]))>256 or len(ranger.get('tracking',{}).get('results',[]))>256:raise ValueError('Invalid ranger snapshot bounds')
 for row in ranger.get('tracking',{}).get('results',[])+ranger.get('targets',[]):
  name=row.get('name','')
  if isinstance(name,str) and name.startswith('@') and ':' in name:
   table,key=name[1:].split(':',1);row['name']=display(table,key,name)
 for item in state.get('inventory',{}).get('items',[])+state.get('items',[])+([state['hip_tool']] if state.get('hip_tool') else []):
  item['name']=item.get('custom_name') or display(item.get('name_table',''),item.get('name_key',''),template_label(item['template'])[0])
  item['customization']=decode_customization(bytes.fromhex(item.get('customization_hex','')))
  item['attributes']=[]
 inspection=out.get('mutation',{}).get('inspection')
 if inspection is not None:
  original=(attributes or {}).get('o'+inspection['id'])
  if original is None:raise ValueError('Missing native creature inspection attributes')
  def resolve(value):
   if isinstance(value,str) and value.startswith('@') and ':' in value:
    table,key=value[1:].split(':',1);return display(table,key,value)
   return value
  inspection['name']=resolve(inspection['name'])
  inspection['attributes']=[{'key':key,'name':display('obj_attr_n',key,key),'value':resolve(value)} for key,value in original.items() if not key.startswith('swgxr.')]
 inventory=state.get('inventory',{});inventory['backend']='core3'
 if attributes is not None:
  state['inventory']=inventory_snapshot({'variables':{'inventory':inventory,'weaponAttributes':attributes}},oid)
  return out
 by_id={i['id']:i for i in inventory.get('items',[])}
 inventory['equipment']=[by_id.get(i['id'],i) for i in inventory.get('equipment',[])]
 if inventory.get('equipped_backpack'):inventory['equipped_backpack']=by_id.get(inventory['equipped_backpack']['id'])
 return out
