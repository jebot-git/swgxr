"""Read-only character-specific SWG asset format helpers."""
import struct
from swg_formats import cstring,parse_iff

def strings(data):return [x.decode('ascii') for x in data.split(b'\0') if x]
def child(node,tag,default=None):return next((x for x in node.children if x.tag==tag),default)
def array(data,fmt):return list(struct.iter_unpack('<'+fmt,data))
def datatable(data):
 r=parse_iff(data);cols=strings(r.first('COLS').data[4:]);types=strings(r.first('TYPE').data);raw=r.first('ROWS').data;n=struct.unpack_from('<I',raw)[0];p=4;rows=[]
 for _ in range(n):
  row={}
  for col,typ in zip(cols,types):
   if typ[0]=='s':value,p=cstring(raw,p)
   else:value=struct.unpack_from('<f' if typ[0]=='f' else '<i',raw,p)[0];p+=4
   row[col]=value
  rows.append(row)
 assert p==len(raw),(p,len(raw))
 return rows

def qmul(a,b):
 w,x,y,z=a;v,i,j,k=b
 return [w*v-x*i-y*j-z*k,w*i+x*v+y*k-z*j,w*j-x*k+y*v+z*i,w*k+x*j-y*i+z*v]
def mirror(v):return [v[0],v[1],-v[2]]
def mirror_quaternion(q):w,x,y,z=q;return [-x,-y,z,w]

def unpack_quaternion(packed,formats):
 """Decode SWG component windows: 11-bit X/Y, 10-bit Z; positive W."""
 import math
 values=[]
 for bits,shift,fmt in zip((11,11,10),(21,10,0),formats):
  for prefix,count in ((128,64),(192,32),(224,16),(240,8),(248,4),(252,2),(254,1)):
   if prefix<=fmt<prefix+count:break
  else:raise ValueError(('Unknown quaternion format',fmt))
  separation=2/(count+1);base=-1+(fmt-prefix+1)*separation
  component=(packed>>shift)&((1<<bits)-1);sign=1<<(bits-1);magnitude=component&(sign-1)
  value=base+(-1 if component&sign else 1)*magnitude*separation/(sign-1)
  values.append(value)
 return [math.sqrt(max(0,1-sum(v*v for v in values))),*values]
