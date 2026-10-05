"""Validated native vehicle requests. No client supplied speed, ownership or seats."""
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
 for key in ('throttle','steer'):
  v=value.get(key)
  if type(v) not in (int,float) or not math.isfinite(v) or not -1<=v<=1:raise ValueError('Invalid vehicle '+key)
  out[key]=v if out['held'] else 0
 return out

def command(action,data):
 if action not in ('status','activate','call','board','dismount','store','recall','pet_call','pet_recall','pet_store'):raise ValueError('Unsupported vehicle action')
 out={'action':action}
 for key in {'activate':['item_id'],'call':['device_id'],'board':['vehicle_id'],'store':['device_id'],'recall':['device_id'],'pet_call':['device_id'],'pet_recall':['device_id'],'pet_store':['device_id']}.get(action,[]):
  v=data.get(key)
  if not isinstance(v,str) or not v.isdigit() or not 0<int(v)<2**64:raise ValueError('Invalid '+key)
  out[key]=v
 if action=='activate':
  key=data.get('request_id','')
  if not isinstance(key,str)or not re.fullmatch(r'[A-Za-z0-9_-]{8,64}',key):raise ValueError('Stable activation request_id required')
  out['request_id']=key
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
 if not out.get('mutation',{}).get('success'):raise ValueError(out.get('error','Vehicle action rejected'))
 return out
