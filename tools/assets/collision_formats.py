"""Decode authored collision/floor data, independently from visual geometry.

Binary layouts are documented by the open-source Core3 appearance/collision
readers. Coordinates returned here are Godot local coordinates (SWG Z mirrored).
No original client implementation is copied into this module.
"""
import struct
from swg_formats import parse_iff, cstring

def mirror(v):
 return [v[0],v[1],-v[2]]

def extent(node):
 tag=node.tag
 if tag=='NULL':return {'type':'null'}
 if tag=='EXBX':
  hi,lo=struct.unpack('<3f',node.first('BOX ').data[:12]),struct.unpack('<3f',node.first('BOX ').data[12:])
  return {'type':'box','min':[lo[0],lo[1],-hi[2]],'max':[hi[0],hi[1],-lo[2]]}
 if tag=='EXSP':
  x,y,z,r=struct.unpack('<4f',node.first('SPHR').data)
  return {'type':'sphere','center':[x,y,-z],'radius':r}
 if tag=='XCYL':
  x,y,z,r,h=struct.unpack('<5f',node.first('CYLN').data)
  return {'type':'cylinder','base':[x,y,-z],'radius':r,'height':h}
 if tag=='CMSH':
  vertices=[v for p in struct.iter_unpack('<3f',node.first('VERT').data) for v in mirror(p)]
  indices=[p[0] for p in struct.iter_unpack('<I',node.first('INDX').data)]
  assert len(indices)%3==0 and (not indices or max(indices)<len(vertices)//3)
  return {'type':'mesh','vertices':vertices,'indices':indices}
 if tag in ('CMPT','DTAL','CPST'):
  container=node.first('CPST') if tag!='CPST' else node
  children=[extent(n) for n in container.children[0].children]
  return {'type':{'CMPT':'component','DTAL':'detail','CPST':'composite'}[tag],'children':children}
 raise ValueError('Unsupported authored collision extent '+tag)

def floor(data):
 root=parse_iff(data);version=root.children[0].tag
 if version not in ('0003','0004','0005','0006'):raise ValueError('Unsupported FLR version '+version)
 offset=4 if version=='0006' else 0
 vertices=[v for p in struct.iter_unpack('<3f',root.first('VERT').data[offset:]) for v in mirror(p)]
 raw=root.first('TRIS').data
 assert (len(raw)-offset)%60==0
 triangles=[];indices=[]
 for pos in range(offset,len(raw),60):
  row={'indices':list(struct.unpack_from('<3I',raw,pos)),
       'id':struct.unpack_from('<I',raw,pos+12)[0],
       'neighbors':list(struct.unpack_from('<3i',raw,pos+16)),
       # FLR versions <=0006 store inverted normals. The original reader
       # negates them after loading; preserve the exact stored SWG vector too.
       'source_normal_raw':list(struct.unpack_from('<3f',raw,pos+28)),
       'normal':[-v for v in mirror(struct.unpack_from('<3f',raw,pos+28))],
       'edge_flags':list(raw[pos+40:pos+43]) if version=='0006' else [int(bool(v)) for v in raw[pos+40:pos+43]],'fallthrough':bool(raw[pos+43]),
       'tag':struct.unpack_from('<i',raw,pos+44)[0],
       'portal_ids':list(struct.unpack_from('<3i',raw,pos+48))}
  assert max(row['indices'])<len(vertices)//3
  triangles.append(row)
  if not row['fallthrough']:indices.extend(row['indices'])
 return {'version':version,'normals_corrected':True,'vertices':vertices,'indices':indices,'triangles':triangles}

def appearance(root, source, read):
 """Return a source-level descriptor; NULL remains distinguishable from errors."""
 appr=next(root.walk('APPR'),None)
 result={'source_appearance':source,'coordinate_system':'Godot instance-local; SWG Z mirrored','fallback':'visual_mesh'}
 if appr is None:
  result.update(status='missing',reason='No APPR collision declaration')
  return result
 children=appr.children[0].children
 try:
  collision=children[1];result['source_extent_type']=collision.tag
  result['extent']=extent(collision)
  result['status']='null' if collision.tag=='NULL' else 'authored'
  result['fallback']='none'
 except Exception as error:
  result.update(status='unsupported',reason=str(error))
 flor=next(appr.walk('FLOR'),None)
 if flor:
  data=flor.first('DATA').data
  if data and data[0]:
   path=cstring(data,1)[0]
   try:result['floor']={'source':path,**floor(read(path))}
   except Exception as error:result['floor_error']={'source':path,'reason':str(error)}
 return result

def godot_matrix(matrix):
 # F*M*F, where F mirrors the source Z axis.
 a,b,c,x,d,e,f,y,g,h,i,z=matrix
 return [a,b,-c,x,d,e,-f,y,-g,-h,i,-z]

def transform_floor(definition, point, direction):
 return {'floor_source':definition.get('source'),'floor_version':definition['version'],'floor_normals_corrected':definition['normals_corrected'],
         'floor_vertices':[v for i in range(0,len(definition['vertices']),3) for v in point(definition['vertices'][i:i+3])],
         'floor_indices':definition['indices'],
         'floor_triangles':[{**t,'normal':direction(t['normal'])} for t in definition['triangles']]}
