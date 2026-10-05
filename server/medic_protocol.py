"""Basic native Medic actions; no client-side HAM, supply or recovery authority."""
from copy import deepcopy
import re,math
try:
 from .character_protocol import decode_customization
 from .datapad_protocol import display,template_label
except ImportError:
 from character_protocol import decode_customization
 from datapad_protocol import display,template_label
ABILITIES=('healdamage','healwound','tenddamage','tendwound','firstaid','quickheal')
ACTIONS=('status','provision','select','heal','holster','return_tool','drag')
def command(action,data):
 if action not in ACTIONS:raise ValueError('Unsupported medical action')
 out={'action':action}
 if 'pose' in data:out['pose']=pose(data['pose'])
 if action=='status':return out
 key=data.get('request_id','')
 if not isinstance(key,str) or not re.fullmatch(r'[A-Za-z0-9_-]{8,64}',key):raise ValueError('Unique medical request_id required')
 out['request_id']=key
 if action=='drag':
  if type(data.get('release',False)) is not bool:raise ValueError('Boolean drag release required')
  out['release']=data.get('release',False)
 for field in (('target_id',) if action=='drag' else () if action=='provision' else ('item_id','target_id') if action=='heal' else ('item_id',)):
  value=data.get(field)
  if not isinstance(value,str) or not value.isdigit() or not 0<int(value)<2**64:raise ValueError('Invalid '+field)
  out[field]=value
 if action in ('select','heal'):
  if data.get('ability') not in ABILITIES:raise ValueError('Unsupported healing ability')
  out['ability']=data['ability']
 return out

def snapshot(raw,oid):
 out=deepcopy(raw)
 if out.get('error'):raise ValueError(out['error'])
 if out.get('character_id')!=str(oid) or out.get('source_kind')!='core3_medic':raise ValueError('Missing owned native medical response')
 state=out.get('state',{})
 if state.get('character_id')!=str(oid) or len(state.get('players',[]))>32:raise ValueError('Invalid medical snapshot')
 inventory=state.get('inventory',{});inventory['backend']='core3'
 items=inventory.get('items',[])+([state['hip_tool']] if state.get('hip_tool') else [])
 for item in items:
  item['name']=item.get('custom_name') or display(item.get('name_table',''),item.get('name_key',''),template_label(item['template'])[0])
  item['customization']=decode_customization(bytes.fromhex(item.get('customization_hex','')))
  item['attributes']=[]
 for p in state.get('players',[]):
  p['customization']=decode_customization(bytes.fromhex(p.pop('customization_hex','')))
  p['race']=p['template'].rsplit('/',1)[-1].removesuffix('.iff').removeprefix('shared_')
 return out

def pose(data):
 if not isinstance(data,dict):raise ValueError('Medical tracked pose required')
 out={}
 for key in ('tracked','crossed','grips'):
  if type(data.get(key)) is not bool:raise ValueError('Boolean tracking flags required')
  out[key]=data[key]
 for key in ('left','right'):
  p=data.get(key)
  if not isinstance(p,list) or len(p)!=3 or any(type(v) not in (int,float) or not math.isfinite(v) or abs(v)>10000 for v in p):raise ValueError('Invalid medical hand position')
  out[key]=p
 return out
