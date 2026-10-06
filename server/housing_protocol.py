"""Only gestures and desired poses cross this boundary; Core3 owns housing."""
import math,re
ACTIONS=tuple('house_'+v for v in ('status','preview','place','deposit','permission_arm','permission','drop','recover'))
ACTIONS+=tuple('house_harvester_'+v for v in ('status','select','active','power','deposit','collect','recover'))
ACTIONS+=tuple('house_factory_'+v for v in ('status','blueprint','remove_blueprint','input','withdraw','collect','active','power','deposit','recover'))
def fields(action,data):
 out={}
 def ident(key):
  v=data.get(key)
  if not isinstance(v,str) or not v.isascii() or not v.isdigit() or not 0<int(v)<2**64:raise ValueError('Native '+key+' required')
  out[key]=v
 def vector(key,n=3):
  v=data.get(key)
  if not isinstance(v,list) or len(v)!=n or any(type(x) not in (int,float) or not math.isfinite(x) or abs(x)>8192 for x in v):raise ValueError('Finite '+key+' required')
  out[key]=v
 if action.startswith('house_factory_'):
  ident('structure_id')
  if action in ('house_factory_blueprint','house_factory_input','house_factory_withdraw','house_factory_collect','house_factory_power'):ident('item_id')
  if action.endswith('_active'):
   if type(data.get('active')) is not bool:raise ValueError('Factory active flag required')
   out['active']=data['active']
  if action.endswith('_deposit'):
   v=data.get('amount')
   if type(v) is not int or not 1<=v<=100000000:raise ValueError('Positive bounded amount required')
   out['amount']=v
  if action.endswith('_recover'):vector('left_hand');vector('right_hand')
 if action.startswith('house_harvester_'):
  ident('structure_id')
  if action.endswith(('_select','_collect')):ident('resource_id')
  if action.endswith('_power'):ident('item_id')
  if action.endswith('_active'):
   if type(data.get('active')) is not bool:raise ValueError('Harvester active flag required')
   out['active']=data['active']
  if action.endswith(('_deposit','_collect')):
   key='amount' if action.endswith('_deposit') else 'quantity';v=data.get(key)
   if type(v) is not int or not 1<=v<=100000000:raise ValueError('Positive bounded '+key+' required')
   out[key]=v
  if action.endswith('_recover'):vector('left_hand');vector('right_hand')
 if action in ('house_preview','house_place'):
  ident('deed_id');vector('placement_position');v=data.get('rotation')
  if type(v)is not int or not 0<=v<=3:raise ValueError('Native quarter-turn rotation required')
  out['rotation']=v
 if action in ('house_deposit','house_permission_arm'):ident('terminal_id')
 if action=='house_deposit':
  v=data.get('amount')
  if type(v)is not int or not 1<=v<=100000000:raise ValueError('Positive upkeep amount required')
  out['amount']=v
 if action=='house_permission_arm':
  if data.get('permission_list') not in ('ENTRY','ADMIN','BAN','VENDOR') or data.get('permission_action') not in ('add','remove'):raise ValueError('Valid house permission required')
  out.update(permission_list=data['permission_list'],permission_action=data['permission_action'])
 if action=='house_permission':
  ident('target_id');v=data.get('arm_id','')
  if not isinstance(v,str) or not re.fullmatch(r'[A-Za-z0-9_-]{8,64}',v):raise ValueError('Current permission selection required')
  out['arm_id']=v
 if action in ('house_drop','house_recover'):ident('item_id')
 if action=='house_drop':
  vector('placement_position');vector('local_quaternion',4)
  if abs(sum(x*x for x in out['local_quaternion'])-1)>.01:raise ValueError('Unit item orientation required')
  if type(data.get('suspended'))is not bool:raise ValueError('A-button suspension flag required')
  out['suspended']=data['suspended']
 if action=='house_recover':vector('left_hand');vector('right_hand')
 return out
