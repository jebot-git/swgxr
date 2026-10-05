"""Read-only PTAT0014 terrain rule decoder, matching pinned SWGEmu Core3 layouts.
Original game data stays in local runtime caches. See terrain attribution notice.
"""
import struct
from swg_formats import parse_iff,cstring

def child(n,tag):return next(c for c in n.children if c.tag==tag)
class Reader:
 def __init__(self,d):self.d=d;self.p=0
 def val(self,f):v=struct.unpack_from('<'+f,self.d,self.p);self.p+=struct.calcsize('<'+f);return v[0] if len(v)==1 else list(v)
 def string(self):v,self.p=cstring(self.d,self.p);return v
 def end(self):assert self.p==len(self.d),(self.p,len(self.d))
def header(n):
 r=Reader(n.first('IHDR').first('DATA').data);return {'enabled':bool(r.val('i')),'name':r.string(),'type':n.tag}
def body(n):return n.children[0]
def rule(n):
 out=header(n);v=body(n);d=child(v,'DATA');r=Reader(d.data);tag=n.tag
 if tag=='BCIR':out.update(center=r.val('2f'),radius=r.val('f'),feather_type=r.val('i'),feather=r.val('f'))
 elif tag=='BREC':
  out.update(rect=r.val('4f'),feather_type=r.val('i'),feather=r.val('f'))
  if v.tag=='0003':out.update(water_enabled=bool(r.val('i')),water_type=r.val('i'),water_height=r.val('f'),water_shader_size=r.val('f'),water_shader=r.string())
 elif tag in ('BPOL','BPLN'):
  out['points']=[r.val('2f') for _ in range(r.val('i'))];out.update(feather_type=r.val('i'),feather=r.val('f'))
  if tag=='BPLN':out['width']=r.val('f')
  else:out.update(water_enabled=bool(r.val('i')),water_height=r.val('f'),water_shader_size=r.val('f'),water_shader=r.string())
 elif tag in ('FHGT','FSLP','FDIR'):out.update(min=r.val('f'),max=r.val('f'),feather_type=r.val('i'),feather=r.val('f'))
 elif tag=='FFRA':
  r=Reader(d.first('PARM').data);out.update(fractal=r.val('i'),feather_type=r.val('i'),feather=r.val('f'),min=r.val('f'),max=r.val('f'),scale=r.val('f'))
 elif tag=='FSHD':out['family']=r.val('i')
 elif tag=='AHCN':out.update(operation=r.val('i'),height=r.val('f'))
 elif tag=='AHFR':
  r=Reader(d.first('PARM').data);out.update(fractal=r.val('i'),operation=r.val('i'),height=r.val('f'))
 elif tag=='AHTR':out.update(flat_ratio=r.val('f'),height=r.val('f'))
 elif tag in ('ASCN','AENV'):out.update(family=r.val('i'),feather_type=r.val('i'),feather=r.val('f'))
 elif tag=='AROA':
  r=Reader(child(d,'DATA').data);out['points']=[r.val('2f') for _ in range(r.val('i'))]
  out.update(width=r.val('f'),family=r.val('i'),feather_type=r.val('i'),feather=r.val('f'),shader_feather_type=r.val('i'),shader_feather=r.val('f'))
  out['segments']=[list(struct.iter_unpack('<3f',s.data)) for s in d.walk('SGMT')]
 elif tag=='ACCN':out.update(operation=r.val('i'),color=r.val('3B'))
 elif tag=='ACRF':
  r=Reader(d.first('PARM').data);out.update(fractal=r.val('i'),operation=r.val('i'),ramp=r.string().replace(chr(92),'/'))
 elif tag=='ACRH':out.update(operation=r.val('i'),min=r.val('f'),max=r.val('f'),ramp=r.string().replace(chr(92),'/'))
 elif tag=='AEXC':pass
 else:
  # Visual detail and flora affectors are inventoried, never misrepresented as evaluated.
  out['raw_hex']=d.data.hex();return out
 r.end();return out

def layer(n):
 out=header(n);v=body(n);r=Reader(child(v,'ADTA').data)
 out.update(invert_boundaries=bool(r.val('I')),invert_filters=bool(r.val('I')),flags=r.val('I'),notes=r.string());r.end()
 out.update(boundaries=[],filters=[],affectors=[],children=[])
 for c in v.children:
  if c.tag=='LAYR':out['children'].append(layer(c))
  elif c.tag.startswith('B'):out['boundaries'].append(rule(c))
  elif c.tag.startswith('F'):out['filters'].append(rule(c))
  elif c.tag.startswith('A') and c.tag!='ADTA':out['affectors'].append(rule(c))
 return out

def generator(node):
 g=node.children[0] if node.tag=='TGEN' else node
 fractals=[]
 for n in g.walk('MFAM'):
  r=Reader(child(n,'DATA').data);f={'id':r.val('i'),'name':r.string()};r.end();r=Reader(n.first('MFRC').first('DATA').data)
  for key,fmt in [('seed','i'),('bias','i'),('bias_value','f'),('gain','i'),('gain_value','f'),('octaves','I'),('frequency_multiplier','f'),('amplitude','f'),('frequency_x','f'),('frequency_z','f'),('offset_x','f'),('offset_z','f'),('combination','I')]:f[key]=r.val(fmt)
  r.end();fractals.append(f)
 shaders=[]
 for n in g.walk('SFAM'):
  r=Reader(n.data);s={'id':r.val('i'),'name':r.string(),'file':r.string(),'color':r.val('3B'),'shader_size':r.val('f'),'weight':r.val('f')};s['shaders']=[{'name':r.string(),'weight':r.val('f')} for _ in range(r.val('i'))];r.end();shaders.append(s)
 layers=[layer(n) for n in child(g,'LYRS').children] if any(c.tag=='LYRS' for c in g.children) else [layer(child(g,'LAYR'))]
 environments=[]
 for n in g.walk('EFAM'):
  r=Reader(n.first('DATA').data);environments.append({'id':r.val('i'),'name':r.string(),'color':r.val('3B'),'weight':r.val('f')});r.end()
 return {'fractals':fractals,'shader_families':shaders,'environment_families':environments,'layers':layers}

def terrain(data):
 root=parse_iff(data);assert root.tag=='PTAT' and root.children[0].tag=='0014'
 v=body(root);r=Reader(child(v,'DATA').data)
 out={'schema_version':1,'source_format':'PTAT0014','source_file':r.string(),'size':r.val('f'),'source_chunk_size':r.val('f'),'source_tiles_per_chunk':r.val('I'),'global_water_enabled':bool(r.val('I')),'global_water_height':r.val('f'),'global_water_shader_size':r.val('f'),'global_water_shader':r.string(),'time_cycle':r.val('f')}
 # Remaining DATA holds original deterministic flora spacing/seeds, retained for later population.
 out['flora_parameters_hex']=r.d[r.p:].hex();out.update(generator(child(v,'TGEN')))
 out['extent']=[-out['size']/2,-out['size']/2,out['size']/2,out['size']/2]
 out['map_chunks']={n.tag:{'bytes':len(n.data)} for n in v.walk() if n.tag in ('WMAP','SMAP')}
 return out
