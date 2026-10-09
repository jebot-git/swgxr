"""Validate native position persistence, never local character storage."""
try:
 from .planets import SUPPORTED_PLANETS, context as planet_context, planet as validate_planet
 from .jtl_protocol import context as jtl_context, local_vector
except ImportError:
 from planets import SUPPORTED_PLANETS, context as planet_context, planet as validate_planet
 from jtl_protocol import context as jtl_context, local_vector
import math,re

def logout_command(data):
 p=data.get('position');heading=data.get('heading_radians',0)
 if not isinstance(p,list)or len(p)!=3 or any(type(v)not in(int,float)or not math.isfinite(v)or abs(v)>(2048 if i==1 else 8192)for i,v in enumerate(p)):raise ValueError('Finite source position required')
 if type(heading)not in(int,float)or not math.isfinite(heading):raise ValueError('Finite source heading required')
 bid=data.get('building_id');cell=data.get('cell_index')
 if not isinstance(bid,str)or not re.fullmatch(r'[0-9]{1,20}',bid)or int(bid)>=2**64 or type(cell)is not int or not 0<=cell<=256 or((int(bid)==0)!=(cell==0)):raise ValueError('Valid source building and cell required')
 out=dict(action='logout',position=p,heading_radians=heading,building_id=bid,cell_index=cell)
 if data.get('zone',data.get('planet'))=='space_tatooine':
  local_vector(p)
  # Cell zero is an original fighter cockpit; native recovery still verifies
  # the actual seated ship or POB parent and never accepts this as world motion.
  if not 0<=cell<=11:raise ValueError('Original owned ship cell required for space logout')
  out.update(jtl_context(data))
 else:out.update(planet_context(data))
 if 'request_id'in data:
  if not isinstance(data['request_id'],str)or not re.fullmatch(r'[A-Za-z0-9_-]{8,64}',data['request_id']):raise ValueError('Stable logout request_id required')
  out['request_id']=data['request_id']
 return out

def snapshot(value,oid):
 if value.get('error'):raise ValueError(value['error'])
 loc=value.get('location',{})
 if value.get('character_id')!=str(oid)or value.get('source_kind')not in('core3_session_status','core3_session_logout')or loc.get('zone')not in SUPPORTED_PLANETS:raise ValueError('Native owned source location unavailable')
 return value
