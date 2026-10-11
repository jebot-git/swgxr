"""Validated native vehicle requests. Owned client motion; native ride properties, ownership and seats."""
try:
 from .planets import context as planet_context
except ImportError:
 from planets import context as planet_context
import math,re
from copy import deepcopy

class ConfirmedVehicleRejection(ValueError):
 mutation_started=False
 confirmed_rejection=True

def vector(value):
 if not isinstance(value,list) or len(value)!=3 or any(type(v) not in (int,float) or not math.isfinite(v) or abs(v)>10000 for v in value):raise ValueError('Finite vehicle hand position required')
 return value

def controls(value):
 if not isinstance(value,dict) or type(value.get('held')) is not bool:raise ValueError('Vehicle grip state required')
 out={'held':value['held']}
 if value.get('mode')=='client_pose':
  vehicle=value.get('vehicle_id')
  if not isinstance(vehicle,str) or not vehicle.isascii() or not vehicle.isdigit() or not 0<int(vehicle)<2**64:raise ValueError('Owned vehicle ID required')
  speed=value.get('speed');heading=value.get('heading_radians')
  if type(speed)not in (int,float) or not math.isfinite(speed) or abs(speed)>100:raise ValueError('Finite bounded vehicle speed required')
  if type(heading)not in (int,float) or not math.isfinite(heading) or abs(heading)>math.pi+.00001:raise ValueError('Finite normalized vehicle heading required')
  out.update(mode='client_pose',vehicle_id=vehicle,position=vector(value.get('position')),speed=speed,heading_radians=heading)
 elif value.get('mode') is not None:raise ValueError('Unsupported vehicle motion mode')
 for key in ('throttle','steer'):
  v=value.get(key)
  if type(v) not in (int,float) or not math.isfinite(v) or not -1<=v<=1:raise ValueError('Invalid vehicle '+key)
  out[key]=v if out['held'] else 0
 return out

def command(action,data):
 if action not in ('ch_status','ch_tame','ch_embolden','ch_enrage','ch_train_mount','ch_train_command','status','activate','call','board','dismount','store','recall','pet_call','pet_recall','pet_store','pet_command'):raise ValueError('Unsupported vehicle action')
 out={'action':action,**planet_context(data)}
 for key in {'activate':['item_id'],'call':['device_id'],'board':['vehicle_id'],'store':['device_id'],'recall':['device_id'],'pet_call':['device_id'],'pet_recall':['device_id'],'pet_store':['device_id'],'pet_command':['device_id'],'ch_tame':['target_id'],'ch_train_mount':['device_id'],'ch_train_command':['device_id']}.get(action,[]):
  v=data.get(key)
  if not isinstance(v,str) or not v.isascii() or not v.isdigit() or not 0<int(v)<2**64:raise ValueError('Invalid '+key)
  out[key]=v
 if action in ('activate','pet_command','ch_tame','ch_embolden','ch_enrage','ch_train_mount','ch_train_command'):
  key=data.get('request_id','')
  if not isinstance(key,str)or not re.fullmatch(r'[A-Za-z0-9_-]{8,64}',key):raise ValueError('Stable activation request_id required')
  out['request_id']=key
 if action=='ch_train_mount':out['hand']=vector(data.get('hand'))
 if action=='ch_train_command':
  number=data.get('command_id')
  if type(number)is not int or number not in (1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,18,22,23):raise ValueError('Invalid creature training command')
  out['command_id']=number
 if action=='pet_command':
  number=data.get('command_id')
  if type(number)is not int or not 1<=number<=24:raise ValueError('Invalid trained pet command')
  out['command_id']=number
  targeted=number in (3,4,5,6,12,13,17,18,19,20,21)
  target=data.get('target_id','')
  if targeted:
   if not isinstance(target,str) or not target.isascii() or not target.isdigit() or not 0<int(target)<2**64:raise ValueError('Native pet target required')
   out['target_id']=target
  elif target!='':raise ValueError('Untargeted pet command cannot carry target')
 if 'position' in data:out['position']=vector(data['position'])
 if 'building_id' in data:
  bid=data['building_id'];cell=data.get('cell_index')
  if not isinstance(bid,str)or not bid.isdigit()or not 0<=int(bid)<2**64 or type(cell)is not int or not 0<=cell<=256 or ((int(bid)==0)!=(cell==0)):raise ValueError('Valid source building and cell required')
  out.update(building_id=bid,cell_index=cell)
 if action=='board':
  if data.get('seat') not in ('driver','passenger'):raise ValueError('Invalid vehicle seat')
  out.update(seat=data['seat'],hand=vector(data.get('hand')))
 if action in ('store','pet_store'):out.update(left=vector(data.get('left')),right=vector(data.get('right')))
 return out

def snapshot(out,oid):
 out=deepcopy(out)
 if out.get("error"):
  if out.get("confirmed_rejection") is True:raise ConfirmedVehicleRejection(out["error"])
  raise ValueError(out["error"])
 if out.get('source_kind')!='core3_vehicles' or out.get('character_id')!=str(oid) or out.get('state',{}).get('character_id')!=str(oid):raise ValueError('Invalid native vehicle response')
 if any(len(out['state'].get(key,[]))>32 for key in ('vehicles','datapad','pets','pet_datapad')):raise ValueError('Vehicle or droid snapshot limit')
 ch=out['state'].get('creature_handler',{})
 if not isinstance(ch,dict) or len(ch.get('candidates',[]))>32:raise ValueError('Creature handler candidate limit')
 if not out.get('mutation',{}).get('success'):raise ValueError(out.get('error','Vehicle action rejected'))
 return out
