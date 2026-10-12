"""Seeded original cube/ribbon asteroid layouts, in source XYZ coordinates.

Independent ran1 implementation and linear control-point sampling. Positions,
style weights, counts, scales and rotations come from the supplied tables.
"""
import math
import struct
from character_formats import qmul
from swg_formats import parse_iff
from prepare_stage import mirror, qmirror

class Random:
    def __init__(self, seed):
        self.state=max(1,abs(int(seed))); self.table=[0]*32
        for i in range(39,-1,-1):
            self.state=self.state*16807%2147483647
            if i<32:self.table[i]=self.state
        self.value=self.table[0]
    def real(self, low=0., high=1.):
        self.state=self.state*16807%2147483647
        index=int(self.value/(1+(2147483646//32)))
        self.value,self.table[index]=self.table[index],self.state
        return low+(high-low)*(self.value/2147483647)

def subtract(a,b):return [x-y for x,y in zip(a,b)]
def cross(a,b):return [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]
def unit(a):
    length=math.sqrt(sum(v*v for v in a))
    if length<1e-9:raise ValueError('Degenerate authored asteroid ribbon')
    return [v/length for v in a]
def sample(points,t):
    at=t*(len(points)-1);i=min(len(points)-2,int(at));f=at-i
    return [a+(b-a)*f for a,b in zip(points[i],points[i+1])]
def quaternion(angles):
    q=[1,0,0,0]
    for axis,angle in zip((1,0,2),angles):
        other=[math.cos(angle/2),0,0,0];other[axis+1]=math.sin(angle/2);q=qmul(q,other)
    return qmirror(q)

def radius(assets,style):
    path=style.get('SharedTemplate','')
    if not style['meshes']:return 1.
    appearance=assets.properties(path).get('appearanceFilename','')
    if appearance:
        root=parse_iff(assets.read(appearance));appr=next(root.walk('APPR'),None)
        if appr:
            sphere=next(appr.children[0].children[0].walk('SPHR'),None)
            if sphere:return struct.unpack('<4f',sphere.data)[3]
    bounds=[assets.meshes[m] for m in style['meshes']]
    lo=[min(b['bounds_min'][k] for b in bounds) for k in range(3)]
    hi=[max(b['bounds_max'][k] for b in bounds) for k in range(3)]
    return math.sqrt(sum((a-b)**2 for a,b in zip(lo,hi)))/2

def field_instances(assets,field):
    rng=Random(field['RandomSeed']);styles=field['FieldStyleTable_rows']
    if not styles:return []
    radii=[radius(assets,s) for s in styles]
    total=sum(s['Likelihood'] for s in styles)
    if total<=0:raise ValueError('Empty original asteroid style distribution')
    def source_vector(text):
        values=[float(v) for v in text.split(',')] if text else []
        if text and len(values)!=3:
            field.setdefault('source_warnings',[]).append('Original three-float scan: '+text)
        # Original sscanf reads at most three floats into a zero-initialized Vector.
        return (values+[0.,0.,0.])[:3]
    points=[source_vector(point) for point in field['SplineControlPoints'].split(':')] if field['Type']==2 else []
    toward=source_vector(field['FaceTowards'])
    field['collision_spheres']=[]
    accepted=[];result=[];attempts=0;r=field['Radius']
    while len(accepted)<field['NumAsteroids']:
        attempts+=1
        if attempts>max(10000,field['NumAsteroids']*1000):raise ValueError('Original asteroid field cannot fit its count')
        if field['Type']==1:p=[field['CenterLocation'+k]+rng.real(-r,r) for k in 'XYZ']
        elif field['Type']==2:
            t=rng.real();p=sample(points,t);tangent=subtract(sample(points,t+.1 if t<.9 else t-.1),p)
            if field['FlattenDepth']>=0:
                x=unit(subtract(p,toward));depth=field['FlattenDepth']
            else:
                # Stable perpendicular of the original spline direction.
                x=unit(cross(tangent,[1,0,0] if abs(tangent[0])<abs(tangent[1]) else [0,1,0]));depth=r
            y=unit(cross(x,tangent));dx=rng.real(-depth,depth);dy=rng.real(-r,r)
            p=[v+a*dx+b*dy for v,a,b in zip(p,x,y)]
        else:raise ValueError('Unsupported original asteroid field type')
        rotation=[rng.real(0,math.tau) for _ in range(3)]
        spin=[rng.real(field['RotationMin'],field['RotationMax']) for _ in range(3)]
        scale=rng.real(field['ScaleMin'],field['ScaleMax']);choice=rng.real()*total
        index=len(styles)-1
        for i,style in enumerate(styles):
            choice-=style['Likelihood']
            if choice<=0:index=i;break
        size=radii[index]*scale
        if any(sum((a-b)**2 for a,b in zip(p,old))<(size+rad)**2 for old,rad in accepted):continue
        accepted.append((p,size))
        if styles[index]['meshes']:field['collision_spheres'].append(dict(position=p,radius=size))
        for mesh in styles[index]['meshes']:
            result.append(dict(mesh=mesh,position=mirror(p),quaternion=quaternion(rotation),scale=scale,spin=spin))
    return result
