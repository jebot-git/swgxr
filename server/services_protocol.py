"""Native terminal services validation and source text resolution."""
try:
 from .housing_protocol import ACTIONS as HOUSING_ACTIONS, fields as housing_fields
 from .fishing_protocol import ACTIONS as FISHING_ACTIONS, fields as fishing_fields
 from .slicing_protocol import ACTIONS as SLICING_ACTIONS, fields as slicing_fields
 from .bounty_protocol import ACTIONS as BOUNTY_ACTIONS, fields as bounty_fields, normalize_snapshot as bounty_snapshot
 from .planets import SUPPORTED_PLANETS, context as planet_context, planet as validate_planet
except ImportError:
 from housing_protocol import ACTIONS as HOUSING_ACTIONS, fields as housing_fields
 from fishing_protocol import ACTIONS as FISHING_ACTIONS, fields as fishing_fields
 from slicing_protocol import ACTIONS as SLICING_ACTIONS, fields as slicing_fields
 from bounty_protocol import ACTIONS as BOUNTY_ACTIONS, fields as bounty_fields, normalize_snapshot as bounty_snapshot
 from planets import SUPPORTED_PLANETS, context as planet_context, planet as validate_planet
from copy import deepcopy
import math,re,json
from pathlib import Path
from functools import lru_cache
try:
 from .datapad_protocol import display,template_label
 from .character_protocol import decode_customization,template_names
 from .inventory_protocol import inventory_snapshot
except ImportError:
 from datapad_protocol import display,template_label
 from character_protocol import decode_customization,template_names
 from inventory_protocol import inventory_snapshot
ACTIONS=('status','open','mission_refresh','mission_accept','mission_abort','delivery_open','delivery_pickup','delivery_complete','bazaar_buy','bazaar_retrieve','bazaar_sell','bazaar_cancel','bank_transfer','pay','crafting_station','travel_purchase','travel_board','trainer_train','skill_forget','vendor_place','vendor_sell','vendor_buy','vendor_retrieve','vendor_cancel','vendor_customize','vendor_recover')
ACTIONS+=('ship_manage','ship_component_install','ship_component_remove','ship_chassis_redeem','ship_register','pilot_begin','pilot_choose','herald_begin','herald_choose','underworld_accept',)+FISHING_ACTIONS+HOUSING_ACTIONS+SLICING_ACTIONS+BOUNTY_ACTIONS+('recruiter_join','recruiter_status_toggle','recruiter_purchase','recruiter_promote','contraband_answer')
MUTATIONS=set(ACTIONS)-{'status','open','delivery_open','fishing_status','slicing_status','house_status','house_preview','house_harvester_status','house_factory_status'}
def command(action,data):
 if action not in ACTIONS:raise ValueError('Unsupported terminal service action.')
 out={'action':action,**planet_context(data)}
 for field,maximum in [('category_id',2147483647),('page',100000)]:
  if field in data:
   value=data[field]
   if type(value) is not int or not 0<=value<=maximum:raise ValueError('Invalid bazaar '+field)
   out[field]=value
 if 'search_scope' in data:
  scope=data['search_scope']
  if not isinstance(scope,str) or scope not in ('local','planet','galaxy','vendor'):raise ValueError('Invalid bazaar search scope')
  out['search_scope']=scope
 if action in MUTATIONS:
  key=data.get('request_id','')
  if not isinstance(key,str) or not re.fullmatch(r'[A-Za-z0-9_-]{8,64}',key):raise ValueError('Unique service request_id required.')
  out['request_id']=key
 if 'position' in data:
  p=data['position']
  if not isinstance(p,list) or len(p)!=3 or any(type(x) not in (int,float) or not math.isfinite(x) or abs(x)>(2048 if i==1 else 8192) for i,x in enumerate(p)):raise ValueError('Finite source position required.')
  out['position']=p
 if 'building_id' in data:
  v=data['building_id'];ci=data.get('cell_index')
  if not isinstance(v,str) or not v.isascii() or not v.isdigit() or not 0<=int(v)<2**64 or type(ci) is not int or not 0<=ci<=256 or ((int(v)==0)!=(ci==0)):raise ValueError('Valid source building and cell required.')
  out.update(building_id=v,cell_index=ci)
 required={
  'ship_manage':('terminal_id','ship_id'),'ship_component_install':('terminal_id','ship_id','component_id'),'ship_component_remove':('terminal_id','ship_id','component_id'),'ship_chassis_redeem':('terminal_id','item_id'),'ship_register':('terminal_id','item_id'),
  'pilot_begin':('terminal_id',),'pilot_choose':('terminal_id',),'herald_begin':('terminal_id',),'herald_choose':('terminal_id',),
  'underworld_accept':('terminal_id',),
  'recruiter_promote':('terminal_id',),'recruiter_join':('terminal_id',),'recruiter_status_toggle':('terminal_id',),'recruiter_purchase':('terminal_id',),'contraband_answer':('scan_id',),
  'vendor_place':('vendor_id',),'vendor_customize':('vendor_id',),'vendor_recover':('vendor_id',),'vendor_sell':('terminal_id','item_id'),'vendor_buy':('terminal_id','listing_id'),'vendor_retrieve':('terminal_id','listing_id'),'vendor_cancel':('terminal_id','listing_id'),
  'delivery_open':('npc_id','mission_id'),'delivery_pickup':('npc_id','mission_id'),'delivery_complete':('npc_id','mission_id','parcel_id'),
  'trainer_train':('terminal_id',),'open':('terminal_id',),'mission_refresh':('terminal_id',),'mission_accept':('terminal_id','mission_id'),
  'mission_abort':('mission_id',),'bazaar_buy':('terminal_id','listing_id'),'bazaar_retrieve':('terminal_id','listing_id'),
  'bazaar_sell':('terminal_id','item_id'),'bazaar_cancel':('terminal_id','listing_id'),'bank_transfer':('terminal_id',),'pay':('target_id',),'crafting_station':('terminal_id','tool_id'),
  'travel_purchase':('terminal_id',),'travel_board':('ticket_id',)}.get(action,())
 for k in set(required)|({'terminal_id'} if data.get('terminal_id') else set()):
  v=data.get(k)
  if not isinstance(v,str) or not v.isascii() or not v.isdigit() or not 0<int(v)<2**64:raise ValueError('Invalid native '+k)
  out[k]=v
 if action in ('ship_component_install','ship_component_remove'):
  slot=data.get('slot')
  if type(slot) is not int or not 0<=slot<=19:raise ValueError('Original ship component slot required.')
  out['slot']=slot
 if action=='ship_chassis_redeem':
  price=data.get('price')
  if type(price) is not int or not 0<=price<=2000000000:raise ValueError('Reviewed native chassis dealer price required.')
  out['price']=price
 if action in ('pilot_choose','herald_choose'):
  option=data.get('option');token=data.get('screen_token','')
  if type(option) is not int or not 0<=option<128 or not isinstance(token,str) or not re.fullmatch(r'[A-Za-z0-9_-]{8,64}',token):raise ValueError('Current native conversation option required.')
  out.update(option=option,screen_token=token)
 if action in ('bank_transfer','pay'):
  n=data.get('amount')
  minimum=0 if action=='pay' else 1
  if type(n) is not int or not minimum<=n<=2000000000:raise ValueError('Valid integer amount required.')
  out['amount']=n
  if action=='pay':
   points=data.get('faction_points',{})
   if not isinstance(points,dict) or set(points)-{'imperial','rebel'} or any(type(v) is not int or not 0<=v<=2000000000 for v in points.values()):raise ValueError('Nonnegative Imperial/Rebel faction amounts required.')
   if not n and not any(points.values()):raise ValueError('Select credits or faction points to send.')
   if points:out['faction_points']={f:points.get(f,0) for f in ('imperial','rebel')}
 if action=='vendor_place':
  p=data.get('placement_position');heading=data.get('placement_heading')
  if not isinstance(p,list) or len(p)!=3 or any(type(x) not in (int,float) or not math.isfinite(x) or abs(x)>(2048 if i==1 else 8192) for i,x in enumerate(p)):raise ValueError('Finite vendor placement position required.')
  if type(heading) not in (int,float) or not math.isfinite(heading) or abs(heading)>math.tau:raise ValueError('Finite vendor placement heading required.')
  if out.get('building_id','0')=='0' or 'position' not in out:raise ValueError('Vendor placement requires player position and source building cell.')
  out.update(placement_position=p,placement_heading=heading)
  out.pop('terminal_id',None)
 if action=='vendor_customize':
  values=data.get('customization')
  if not isinstance(values,dict) or len(values)>128 or any(not isinstance(k,str) or not re.fullmatch(r'[A-Za-z0-9_/]{1,128}',k) or type(v) is not int or not 0<=v<=255 for k,v in values.items()):raise ValueError('Valid original vendor customization required.')
  out['customization']=values
 if action in ('vendor_recover','vendor_customize'):out.pop('terminal_id',None)
 if action in ('trainer_train','skill_forget'):
  skill=data.get('skill_id')
  if not isinstance(skill,str) or not re.fullmatch(r'[a-z][a-z0-9_]{1,95}',skill):raise ValueError('Native trainer skill_id required.')
  out['skill_id']=skill
  if action=='skill_forget':out.pop('terminal_id',None)
 if action=='bank_transfer':
  if data.get('direction') not in ('deposit','withdraw'):raise ValueError('Choose deposit or withdraw.')
  out['direction']=data['direction']
 if action in ('bazaar_buy','bazaar_sell','vendor_buy','vendor_sell'):
  limit=99999999 if action.startswith('vendor_') else 20000
  n=data.get('price')
  if type(n) is not int or not 0<n<=limit:raise ValueError('Invalid original bazaar price.')
  out['price']=n
  if 'max_price' in data:
   maximum=data['max_price']
   if type(maximum) is not int or not n<=maximum<=limit:raise ValueError('Invalid maximum bid.')
   out['max_price']=maximum
 if action in ('bazaar_sell','vendor_sell'):
  description=data.get('description','')
  if not isinstance(description,str) or len(description)>512:raise ValueError('Bazaar description too long.')
  out['description']=description
  if type(data.get('auction',False)) is not bool:raise ValueError('auction must be boolean.')
  out['auction']=data.get('auction',False)
  if action=='vendor_sell' and out['auction']:raise ValueError('Vendor listings use fixed prices.')
  if type(data.get('galactic_search',True)) is not bool:raise ValueError('galactic_search must be boolean.')
  out['galactic_search']=data.get('galactic_search',True)
 if action=='travel_board' or action.startswith('delivery_'):out.pop('terminal_id',None)
 if action=='travel_purchase':
  destination=data.get('destination_id')
  if not isinstance(destination,str) or not re.fullmatch(r"[A-Za-z0-9 '\-]{1,100}",destination):raise ValueError('Native destination name required.')
  if type(data.get('round_trip',False)) is not bool:raise ValueError('round_trip must be boolean.')
  out.update(destination_id=destination,round_trip=data.get('round_trip',False))
  if 'destination_planet' in data:out['destination_planet']=validate_planet(data['destination_planet'])
 if action=='recruiter_promote':
  if type(data.get('expected_rank')) is not int or not 0<=data['expected_rank']<=15:raise ValueError('Current original faction rank required.')
  out['expected_rank']=data['expected_rank']
 if action=='recruiter_status_toggle':
  if type(data.get('expected_status')) is not int or data['expected_status'] not in (0,1):raise ValueError('Current native faction status required.')
  out['expected_status']=data['expected_status']
 if action=='recruiter_purchase':
  reward=data.get('reward_id')
  if not isinstance(reward,str) or not re.fullmatch(r'(imperial|rebel):(weaponsArmor|uniforms|furniture):[a-z0-9_]{1,96}',reward):raise ValueError('Supported original faction reward required.')
  out['reward_id']=reward
 if action=='contraband_answer':
  if type(data.get('accept')) is not bool:raise ValueError('Choose pay or refuse the original contraband fine.')
  out['accept']=data['accept'];out.pop('terminal_id',None)
 if action in HOUSING_ACTIONS:out.update(housing_fields(action,data))
 if action in FISHING_ACTIONS:out.update(fishing_fields(action,data))
 if action in SLICING_ACTIONS:out.update(slicing_fields(action,data))
 if action in BOUNTY_ACTIONS:
  out.update(bounty_fields(action,data));out.pop('terminal_id',None)
 return out

def label(value):
 if isinstance(value,str) and re.fullmatch(r'@?[A-Za-z0-9_/]+:[A-Za-z0-9_]+',value):
  table,key=value.lstrip('@').split(':',1)
  return display(table,key,value)
 return value

@lru_cache(maxsize=1)
def categories():
 path=Path(__file__).resolve().parents[1]/'runtime/assets/services/bazaar_categories.json'
 if not path.exists():return [],['Original bazaar category dataset has not been prepared.']
 catalog=json.loads(path.read_text());nodes={row['id']:row for row in catalog['nodes']}
 def expand(oid):
  row=nodes[oid]
  return {'id':oid,'name':row['label'],'children':[expand(child) for child in row.get('children',[])]}
 return [{'id':0,'name':nodes[0]['label'],'children':[]}]+[expand(child) for child in nodes[0]['children']],catalog.get('limitations',[])

def snapshot(raw,oid,attributes=None):
 state=deepcopy(raw)
 if state.get('error'):raise ValueError(state['error'])
 if state.get('character_id')!=str(oid) or state.get('source_kind')!='core3_services':raise ValueError('Owned native service snapshot required.')
 if len(state.get('terminals',[]))>128 or len(state.get('tickets',[]))>256:raise ValueError('Native services snapshot exceeds bounds.')
 if len(state.get('delivery_contacts',[]))>32 or len(state.get('parcels',[]))>16:raise ValueError('Native delivery snapshot exceeds bounds.')
 if len(state.get('vendors',[]))>64 or len(state.get('placed_vendors',[]))>64:raise ValueError('Native vendor snapshot exceeds bounds.')
 if 'bounty' in state:state['bounty']=bounty_snapshot(state['bounty'],label)
 for vendor in state.get('vendors',[])+state.get('placed_vendors',[]):
  if not isinstance(vendor.get('id'),str) or not vendor['id'].isdigit():raise ValueError('Native vendor identity required.')
  vendor['shared_template']=template_names().get(vendor.get('client_crc'),'')
  vendor['customization']=decode_customization(bytes.fromhex(vendor.pop('customization_hex','')))
  vendor['name']=vendor.pop('custom_name','') or template_label(vendor['shared_template'] or vendor.get('template',''))[0]
  vendor.update(category='vendors',type='vendor',deletable=False,source='core3_owned_vendor')
  vendor['description']='Grip and pull this vendor from the datapad. Move the hologram by hand; trigger places, releasing grip cancels.'
 if 'fishing' in state:
  state['fishing']['message']=label(state['fishing'].get('message',''))
  for bait in state['fishing'].get('baits',[]):bait['name']=template_label(bait.get('template',''))[0]
 mutation=state.pop('mutation',{'success':True})
 if state.get('terminal',{}).get('kind') in ('bazaar','vendor'):
  tree,limitations=categories();state['terminal']['categories']=deepcopy(tree);state['terminal']['category_limitations']=limitations
 appearance=state.get('player',{}).get('appearance',{})
 if appearance:
  appearance['customization']=decode_customization(bytes.fromhex(appearance.pop('customization_hex','')))
  appearance['shared_template']=template_names().get(appearance.get('client_crc'),'')
 for terminal in state.get('terminals',[])+state.get('delivery_contacts',[])+([state['terminal']] if state.get('terminal') else []):
  terminal['name']=label(terminal.get('name',''))
  if terminal.get('kind')=='mission' and terminal.get('terminal_type') in ('artisan','scout','bounty','entertainer','imperial','rebel'):
   terminal['name']=label('@terminal_name:terminal_mission_'+terminal['terminal_type'])
  if terminal.get('kind') in ('pilot_trainer','herald'):
   terminal['dialogue']=label(terminal.get('dialogue',''))
   for option in terminal.get('options',[]):option['name']=label(option.get('name',''))
  if terminal.get('kind') in ('ship_outfit','chassis_dealer'):
   for option in terminal.get('options',[]):
    item=label(option.get('item_name',''));operation=option.get('operation','')
    if operation=='ship_chassis_redeem':option['name']=f"Redeem {item} · {option['price']} credits"
    elif operation=='ship_register':option['name']=f'Register {item}'
    elif operation in ('ship_component_install','ship_component_remove'):option['name']=('Install ' if operation.endswith('install') else 'Remove ')+option.get('slot_name','').replace('_',' ').title()+': '+item
  if terminal.get('kind')=='delivery':
   terminal['mission_name']=label(terminal.get('mission_name',''))
   if 'dialogue' in terminal:terminal['dialogue']=label(terminal['dialogue'])
  if terminal.get('kind')=='recruiter':
   for field in ('recruiter_text','rank_name','next_rank_name'):terminal[field]=label(terminal.get(field,''))
  if terminal.get('kind')=='trainer':terminal['trainer_text']=label(terminal.get('trainer_text',''))
  for kind in ('missions','listings','tools','skills'):
   for row in terminal.get(kind,[]):
    row['name']=label(row.get('name',''));row['description']=label(row.get('description',''))
    if kind=='missions':row['target']=label(row.get('target',''))
    if kind=='skills':row['xp_name']=label(row.get('xp_name',''))
 for row in state.get('missions',[]):
  row['target']=label(row.get('target',''))
  row['name']=label(row.get('name',''));row['description']=label(row.get('description',''))
 for parcel in state.get('parcels',[]):
  if not isinstance(parcel.get('id'),str) or not parcel['id'].isdigit() or not isinstance(parcel.get('mission_id'),str) or not parcel['mission_id'].isdigit():raise ValueError('Native owned mission parcel identity required.')
  parcel['shared_template']=template_names().get(parcel.get('client_crc'),'')
  parcel['customization']=decode_customization(bytes.fromhex(parcel.get('customization_hex','')))
  fallback=template_label(parcel['shared_template'] or parcel.get('template',''))[0]
  parcel['name']=parcel.pop('custom_name','') or display(parcel.pop('name_table',''),parcel.pop('name_key',''),fallback)
  parcel['description']=label(parcel.get('description',''))
  parcel['attributes']={'mission_id':parcel['mission_id'],'receiver_id':parcel.get('receiver_id',''),'stage':parcel.get('stage','deliver'),'native_inventory_object':True}
  parcel.update(category='data',type='mission_parcel',deletable=False,source='core3_delivery_objective')
 if 'dialogue' in mutation:mutation['dialogue']=label(mutation['dialogue'])
 if state.get('terminal',{}).get('kind')=='mission':state['terminal'].setdefault('missions',[]).extend(deepcopy(state.get('missions',[])))
 if state.get('inventory'):state['inventory']=inventory_snapshot({'variables':{'inventory':state['inventory'],'weaponAttributes':attributes or {}}},oid)
 if 'housing' in state:
  owned={item['id']:item for item in state.get('inventory',{}).get('items',[])}
  state['housing']['deeds']=[dict(owned[row['id']],category='data',type='factory_deed' if owned[row['id']].get('structure_template','').startswith('object/installation/manufacture/') else 'harvesting_deed',deletable=False,description='Grip and pull to preview placement. Trigger builds; releasing grip cancels.') for row in state['housing'].get('deeds',[]) if row.get('id') in owned]

 shuttle=state.get('shuttle',{})
 state['shuttles']=[shuttle] if shuttle else []
 if mutation.get('transport_destination'):
  state['transport']=state.get('transport',{'id':'services_'+str(oid)+'_'+str(mutation.get('request_id','travel')),'kind':'shuttle','destination':mutation['transport_destination']})
 out={'ok':mutation.get('success') is True,'backend':'core3','source_kind':'core3_services','character_id':str(oid),'state':state,'mutation':mutation}
 if state.get('transport'):out['transport']=state['transport']
 return out
