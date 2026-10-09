"""Basic native Medic actions; no client-side HAM, supply or recovery authority."""
try:
 from .planets import context as planet_context
except ImportError:
 from planets import context as planet_context
from copy import deepcopy
import re,math
try:
 from .character_protocol import decode_customization
 from .datapad_protocol import display,template_label
except ImportError:
 from character_protocol import decode_customization
 from datapad_protocol import display,template_label
ABILITIES=('tenddamage','firstaid','quickheal','healmind')
DOCTOR_ABILITIES=('reviveplayer','extinguishfire','healstate')
COMBAT_MEDIC_ABILITIES=('applypoison','applydisease')
ACTIONS=('status','provision','select','heal','holster','return_tool','drag','bandage','wound_pack','medical_item','doctor','combat_medic')
def command(action,data):
 if action not in ACTIONS:raise ValueError('Unsupported medical action')
 out={'action':action,**planet_context(data)}
 if 'pose' in data:out['pose']=pose(data['pose'])
 if action=='status':return out
 key=data.get('request_id','')
 if not isinstance(key,str) or not re.fullmatch(r'[A-Za-z0-9_-]{8,64}',key):raise ValueError('Unique medical request_id required')
 out['request_id']=key
 if action in ('bandage','wound_pack','medical_item','doctor','combat_medic') and 'pose' not in out:raise ValueError('Tracked medical pose required')
 if action=='drag':
  if type(data.get('release',False)) is not bool:raise ValueError('Boolean drag release required')
  out['release']=data.get('release',False)
 for field in (('target_id',) if action in ('drag','bandage') else () if action=='provision' else ('item_id','target_id') if action in ('heal','wound_pack','medical_item','doctor','combat_medic') else ('item_id',)):
  value=data.get(field)
  if not isinstance(value,str) or not value.isdigit() or not 0<int(value)<2**64:raise ValueError('Invalid '+field)
  out[field]=value
 if action in ('select','heal'):
  if data.get('ability') not in ABILITIES:raise ValueError('Unsupported healing ability')
  out['ability']=data['ability']
  if action=='heal' and out['ability']=='healmind' and 'pose' not in out:raise ValueError('Tracked medical pose required')
 if action in ('doctor','combat_medic'):
  if data.get('ability') not in (DOCTOR_ABILITIES if action=='doctor' else COMBAT_MEDIC_ABILITIES):raise ValueError('Unsupported medical tool ability')
  out['ability']=data['ability']
  if action=='combat_medic' or out['ability']=='healstate':
   value=data.get('focus_id')
   if not isinstance(value,str) or not value.isdigit() or not 0<int(value)<2**64:raise ValueError('Held Doctor tool focus_id required')
   out['focus_id']=value
 return out

def snapshot(raw,oid):
 out=deepcopy(raw)
 if out.get('error'):raise ValueError(out['error'])
 if out.get('character_id')!=str(oid) or out.get('source_kind')!='core3_medic':raise ValueError('Missing owned native medical response')
 state=out.get('state',{})
 if state.get('character_id')!=str(oid) or any(len(state.get(key,[]))>32 for key in ('players','companions')):raise ValueError('Invalid medical snapshot')
 combat=state.get('combat_medic',{})
 if any(len(combat.get(key,[]))>limit for key,limit in (('abilities',2),('supplies',256),('targets',32))):raise ValueError('Combat Medic snapshot exceeds bounds')
 inventory=state.get('inventory',{});inventory['backend']='core3'
 items=inventory.get('items',[])+([state['hip_tool']] if state.get('hip_tool') else [])
 for item in items:
  item['name']=item.get('custom_name') or item.get('display_name') or display(item.get('name_table',''),item.get('name_key',''),template_label(item['template'])[0])
  item['customization']=decode_customization(bytes.fromhex(item.get('customization_hex','')))
  item['attributes']=[]
 names={str(item['id']):item['name'] for item in items}
 for supply in combat.get('supplies',[]):
  if str(supply.get('item_id','')) in names:supply['label']=names[str(supply['item_id'])]
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
