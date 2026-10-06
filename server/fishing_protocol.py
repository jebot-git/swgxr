"""VR gesture input only; Core3's fishing clock, bait and catches are authoritative."""
import math,re
ACTIONS=tuple('fishing_'+name for name in ('status','open','bait','cast','action','stop','stow','collect'))
def fields(action,data):
 out={}
 for key in ('rod_id','bait_id') if action=='fishing_bait' else ('rod_id',):
  value=data.get(key)
  if not isinstance(value,str) or not value.isascii() or not value.isdigit() or not 0<int(value)<2**64:raise ValueError('Native fishing '+key+' required')
  out[key]=value
 if action=='fishing_cast':
  p=data.get('cast_position')
  if not isinstance(p,list) or len(p)!=3 or any(type(v) not in (float,int) or not math.isfinite(v) or abs(v)>8192 for v in p):raise ValueError('Finite fishing cast position required')
  out['cast_position']=p
 if action=='fishing_action':
  gesture=data.get('gesture');session=data.get('session_id','')
  if type(gesture)is not int or not 1<=gesture<=4:raise ValueError('Fishing gesture must be up, right, left or reel')
  if not isinstance(session,str) or not re.fullmatch(r'[A-Za-z0-9_-]{8,64}',session):raise ValueError('Current fishing session required')
  out.update(gesture=gesture,session_id=session)
 return out
