"""Validated native scout actions; no local rewards, buffs or camp authority."""
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
ACTIONS=('holster','return_tool','status','forage','trap','camp','disband','mask_scent','discard_mask_scent','burst_run')
def command(action,data):
 if action not in ACTIONS:raise ValueError('Unsupported scout action')
 p=data.get('position')
 if not isinstance(p,list) or len(p)!=3 or any(type(v) not in (int,float) or not math.isfinite(v) or abs(v)>(2048 if i==1 else 8192) for i,v in enumerate(p)):raise ValueError('Finite Tatooine position required')
 out={'action':action,'position':p,'planet':'tatooine'}
 if 'posture' in data:
  if data['posture'] not in ('standing','kneeling','prone'):raise ValueError('Invalid tracked posture')
  out['posture']=data['posture']
 if action!='status':
  key=data.get('request_id','')
  if not isinstance(key,str) or not re.fullmatch(r'[A-Za-z0-9_-]{8,64}',key):raise ValueError('Unique scout request_id required')
  out['request_id']=key
 for field in {'holster':('item_id',),'return_tool':('item_id',),'trap':('item_id','target_id'),'camp':('item_id',),'disband':('terminal_id',)}.get(action,()):
  value=data.get(field)
  if not isinstance(value,str) or not value.isdigit() or not 0<int(value)<2**64:raise ValueError('Invalid '+field)
  out[field]=value
 return out

def snapshot(raw,oid,attributes=None):
 out=deepcopy(raw)
 if out.get('error'):raise ValueError(out['error'])
 if out.get('character_id')!=str(oid) or out.get('source_kind')!='core3_scout':raise ValueError('Missing owned native scout response')
 state=out.get('state',{})
 if state.get('character_id')!=str(oid) or len(state.get('targets',[]))>96 or len(state.get('camps',[]))>16:raise ValueError('Invalid scout snapshot bounds')
 for item in state.get('inventory',{}).get('items',[])+state.get('items',[])+([state['hip_tool']] if state.get('hip_tool') else []):
  item['name']=item.get('custom_name') or display(item.get('name_table',''),item.get('name_key',''),template_label(item['template'])[0])
  item['customization']=decode_customization(bytes.fromhex(item.get('customization_hex','')))
  item['attributes']=[]
 inventory=state.get('inventory',{});inventory['backend']='core3'
 if attributes is not None:
  state['inventory']=inventory_snapshot({'variables':{'inventory':inventory,'weaponAttributes':attributes}},oid)
  return out
 by_id={i['id']:i for i in inventory.get('items',[])}
 inventory['equipment']=[by_id.get(i['id'],i) for i in inventory.get('equipment',[])]
 if inventory.get('equipped_backpack'):inventory['equipped_backpack']=by_id.get(inventory['equipped_backpack']['id'])
 return out
