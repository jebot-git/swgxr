"""Self-contained VRM 1.0 packaging and structural validation (stdlib only)."""
from __future__ import annotations
import json
import math
import struct

class ExportError(ValueError):
    pass

BONES = {'hips':'root', 'spine':'spine1', 'chest':'spine2', 'upperChest':'spine3',
         'neck':'neck', 'head':'head', 'jaw':'jaw', 'leftEye':'leye', 'rightEye':'reye'}
PARENTS = {'spine':'hips', 'chest':'spine', 'upperChest':'chest', 'neck':'upperChest',
           'head':'neck', 'jaw':'head', 'leftEye':'head', 'rightEye':'head'}
REQUIRED = {'hips','spine','head'}
for side, prefix in [('left','l'),('right','r')]:
    for target, source, parent in [('UpperLeg','thigh','hips'),('LowerLeg','shin',side+'UpperLeg'),
        ('Foot','ankle',side+'LowerLeg'),('Toes','toe',side+'Foot'),('Shoulder','clav','upperChest'),
        ('UpperArm','arm',side+'Shoulder'),('LowerArm','forearm',side+'UpperArm'),('Hand','wrist',side+'LowerArm')]:
        BONES[side+target] = prefix+source
        PARENTS[side+target] = parent
        if target not in ('Toes','Shoulder'): REQUIRED.add(side+target)
    for finger, source in [('Thumb','thumb'),('Index','index'),('Middle','middle'),('Ring','ring'),('Little','pinky')]:
        parts = ['Metacarpal','Proximal','Distal'] if finger=='Thumb' else ['Proximal','Intermediate','Distal']
        for i, part in enumerate(parts):
            key = side+finger+part
            BONES[key] = prefix+source+f'{i+1:02}'
            PARENTS[key] = side+'Hand' if i==0 else side+finger+parts[i-1]

def read_glb(data: bytes) -> tuple[dict, bytes]:
    if len(data)<20 or struct.unpack_from('<4sII',data)!=(b'glTF',2,len(data)):
        raise ExportError('Invalid GLB header or length.')
    chunks=[]; pos=12
    while pos<len(data):
        if pos+8>len(data): raise ExportError('Truncated GLB chunk.')
        length,kind=struct.unpack_from('<II',data,pos);pos+=8
        if length%4 or pos+length>len(data): raise ExportError('Invalid GLB chunk alignment/length.')
        chunks.append((kind,data[pos:pos+length]));pos+=length
    if not chunks or chunks[0][0]!=0x4E4F534A or len(chunks)>2:
        raise ExportError('Expected JSON and embedded BIN chunks.')
    if len(chunks)!=2 or chunks[1][0]!=0x004E4942: raise ExportError('An embedded BIN chunk is required.')
    try: document=json.loads(chunks[0][1])
    except (ValueError,UnicodeError) as error: raise ExportError('Invalid GLB JSON.') from error
    return document,chunks[1][1]

def write_glb(document:dict, binary:bytes)->bytes:
    payload=json.dumps(document,separators=(',',':'),ensure_ascii=False,allow_nan=False).encode()
    payload+=b' '*((-len(payload))%4);binary+=b'\0'*((-len(binary))%4)
    total=12+8+len(payload)+8+len(binary)
    return struct.pack('<4sII',b'glTF',2,total)+struct.pack('<II',len(payload),0x4E4F534A)+payload+struct.pack('<II',len(binary),0x004E4942)+binary

def _index(index, values, label):
    if type(index)!=int or not 0<=index<len(values):raise ExportError(f'Invalid {label} index: {index!r}')
    return values[index]

def accessor_values(index:int,document:dict,binary:bytes):
    accessor=document['accessors'][index];view=document['bufferViews'][accessor['bufferView']]
    formats={5120:'b',5121:'B',5122:'h',5123:'H',5125:'I',5126:'f'}
    dimensions={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}
    fmt='<'+formats[accessor['componentType']]*dimensions[accessor['type']]
    stride=view.get('byteStride',struct.calcsize(fmt))
    start=view.get('byteOffset',0)+accessor.get('byteOffset',0)
    for i in range(accessor['count']):
        values=struct.unpack_from(fmt,binary,start+i*stride)
        if accessor.get('normalized'):
            maximum={5121:255,5123:65535}.get(accessor['componentType'])
            if maximum is None:raise ExportError('Unsupported normalized skin weights.')
            values=tuple(value/maximum for value in values)
        yield values

def validate(document:dict,binary:bytes,require_vrm:bool=True)->dict:
    if document.get('asset',{}).get('version')!='2.0':raise ExportError('Expected glTF 2.0.')
    buffers=document.get('buffers',[])
    if len(buffers)!=1 or 'uri' in buffers[0] or not 0<=len(binary)-buffers[0].get('byteLength',-4)<=3:
        raise ExportError('Export must use one complete embedded buffer.')
    views=document.get('bufferViews',[]); accessors=document.get('accessors',[])
    component_sizes={5120:1,5121:1,5122:2,5123:2,5125:4,5126:4}
    dimensions={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT2':4,'MAT3':9,'MAT4':16}
    for view in views:
        offset=view.get('byteOffset',0);length=view.get('byteLength',-1)
        if view.get('buffer')!=0 or offset<0 or length<0 or offset+length>buffers[0]['byteLength']:
            raise ExportError('Buffer view extends outside embedded data.')
    for accessor in accessors:
        if 'sparse' in accessor:raise ExportError('Sparse accessors are unsupported by this exporter validator.')
        view=_index(accessor.get('bufferView'),views,'accessor buffer view')
        width=component_sizes.get(accessor.get('componentType'),0)*dimensions.get(accessor.get('type'),0)
        count=accessor.get('count',0);stride=view.get('byteStride',width);offset=accessor.get('byteOffset',0)
        if not width or count<=0 or stride<width or offset<0 or offset+(count-1)*stride+width>view['byteLength']:
            raise ExportError('Accessor data is truncated or malformed.')
    nodes=document.get('nodes',[]);parents={}
    for index,node in enumerate(nodes):
        for child in node.get('children',[]):
            _index(child,nodes,'child node')
            if child in parents:raise ExportError('A node has multiple parents.')
            parents[child]=index
        if any(not math.isfinite(float(x)) for key in ['translation','rotation','scale','matrix'] for x in node.get(key,[])):
            raise ExportError('Nonfinite node transform.')
        if any(x<=0 for x in node.get('scale',[1,1,1])):raise ExportError('Nonpositive node scale.')
    for index in range(len(nodes)):
        chain=set();current=index
        while current in parents:
            if current in chain:raise ExportError('Cyclic node hierarchy.')
            chain.add(current);current=parents[current]
    scenes=document.get('scenes',[])
    scene=_index(document.get('scene',0),scenes,'scene')
    for index in scene.get('nodes',[]):_index(index,nodes,'scene root')
    images=document.get('images',[])
    for image in images:
        if 'uri' in image:raise ExportError('External textures are not permitted in a portable VRM.')
        view=_index(image.get('bufferView'),views,'image buffer view');start=view.get('byteOffset',0)
        if image.get('mimeType')=='image/png':
            if binary[start:start+8]!=b'\x89PNG\r\n\x1a\n':raise ExportError('Invalid embedded PNG.')
        elif image.get('mimeType')=='image/jpeg':
            if binary[start:start+2]!=b'\xff\xd8':raise ExportError('Invalid embedded JPEG.')
        else:raise ExportError('Unsupported embedded image format.')
    for texture in document.get('textures',[]):_index(texture.get('source'),images,'texture source')
    skins=document.get('skins',[])
    if not skins:raise ExportError('Avatar has no skin.')
    joint_nodes=set()
    for skin in skins:
        joints=skin.get('joints',[])
        if not joints or len(set(joints))!=len(joints):raise ExportError('Invalid skin joints.')
        for joint in joints:_index(joint,nodes,'skin joint');joint_nodes.add(joint)
        bind=_index(skin.get('inverseBindMatrices'),accessors,'inverse bind accessor')
        if bind.get('type')!='MAT4' or bind.get('componentType')!=5126 or bind.get('count')!=len(joints):
            raise ExportError('Skin inverse binds do not match its joints.')
    meshes=document.get('meshes',[]);materials=document.get('materials',[]);primitives=0;skinned=0
    for node in nodes:
        if 'mesh' not in node:continue
        mesh=_index(node['mesh'],meshes,'mesh')
        if 'skin' in node:_index(node['skin'],skins,'skin');skinned+=1
        for primitive in mesh.get('primitives',[]):
            primitives+=1;attributes=primitive.get('attributes',{})
            if 'POSITION' not in attributes:raise ExportError('Mesh lacks positions.')
            count=_index(attributes['POSITION'],accessors,'position')['count']
            for value in attributes.values():
                if _index(value,accessors,'attribute')['count']!=count:raise ExportError('Mismatched vertex counts.')
            if 'indices' in primitive:_index(primitive['indices'],accessors,'indices')
            if 'material' in primitive:_index(primitive['material'],materials,'material')
            if 'skin' in node and not {'JOINTS_0','WEIGHTS_0'}<=attributes.keys():raise ExportError('Skinned mesh has no joint weights.')
            if 'skin' in node:
                joint_accessor=accessors[attributes['JOINTS_0']];weight_accessor=accessors[attributes['WEIGHTS_0']]
                if joint_accessor['type']!='VEC4' or joint_accessor['componentType'] not in (5121,5123) or weight_accessor['type']!='VEC4':
                    raise ExportError('Invalid skin attribute types.')
                joints_count=len(skins[node['skin']]['joints'])
                joints=accessor_values(attributes['JOINTS_0'],document,binary)
                weights=accessor_values(attributes['WEIGHTS_0'],document,binary)
                for vertex_joints,vertex_weights in zip(joints,weights):
                    if any(joint>=joints_count for joint in vertex_joints):raise ExportError('Vertex references a nonexistent skin joint.')
                    if any(not math.isfinite(weight) or weight<0 for weight in vertex_weights) or abs(sum(vertex_weights)-1)>0.01:
                        raise ExportError('Skin weights must be finite, nonnegative and normalized.')
            for position in accessor_values(attributes['POSITION'],document,binary):
                if any(not math.isfinite(value) for value in position):raise ExportError('Nonfinite vertex position.')
    if not primitives or not skinned:raise ExportError('Avatar has no skinned geometry.')
    human={}
    if require_vrm:
        extension=document.get('extensions',{}).get('VRMC_vrm',{})
        if extension.get('specVersion')!='1.0' or 'VRMC_vrm' not in document.get('extensionsUsed',[]):raise ExportError('Missing VRM 1.0 extension.')
        meta=extension.get('meta',{})
        if not meta.get('name') or not meta.get('authors') or meta.get('licenseUrl')!='https://vrm.dev/licenses/1.0/':raise ExportError('Incomplete VRM metadata.')
        human=extension.get('humanoid',{}).get('humanBones',{})
        if REQUIRED-human.keys():raise ExportError('Missing required humanoid bones: '+', '.join(sorted(REQUIRED-human.keys())))
        assigned=[entry['node'] for entry in human.values()]
        if len(assigned)!=len(set(assigned)):raise ExportError('Humanoid bones share nodes.')
        for name,entry in human.items():
            node=entry['node'];_index(node,nodes,'humanoid bone')
            if node not in joint_nodes:raise ExportError('Humanoid bone is not a skin joint: '+name)
            expected=PARENTS.get(name)
            while expected and expected not in human:expected=PARENTS.get(expected)
            if expected:
                chain=set();current=node
                while current in parents:current=parents[current];chain.add(current)
                if human[expected]['node'] not in chain:raise ExportError('Invalid humanoid ancestry: '+name)
    return {'nodes':len(nodes),'meshes':len(meshes),'skinned_meshes':skinned,'primitives':primitives,
            'images':len(images),'skins':len(skins),'humanoid_bones':len(human),'embedded':True}

def make_vrm(data:bytes,name:str,author:str='',bone_nodes:dict|None=None,source_forward:str='+Z')->tuple[bytes,dict]:
    document,binary=read_glb(data);validate(document,binary,False)
    nodes=document['nodes'];by_name={}
    for index,node in enumerate(nodes):by_name.setdefault(node.get('name',''),[]).append(index)
    human={}
    for target,source in BONES.items():
        candidates=[bone_nodes[source]] if bone_nodes and source in bone_nodes else by_name.get(source,[])
        if len(candidates)>1:raise ExportError('Ambiguous exported bone name: '+source)
        if candidates:human[target]={'node':candidates[0]}
    # The Godot converter exports +Z. Only rotate legacy -Z intermediates;
    # never double-rotate a converter which already normalized its forward axis.
    if source_forward not in ('+Z','-Z'):raise ExportError('Unknown source forward orientation.')
    scene=document['scenes'][document.get('scene',0)]
    wrapper={'name':'VRMAvatar','children':scene['nodes'][:]}
    if source_forward=='-Z':wrapper['rotation']=[0,1,0,0]
    root=len(nodes);nodes.append(wrapper);scene['nodes']=[root]
    meta={'name':name,'version':'1.0','authors':['Sony Online Entertainment / LucasArts (original SWG assets)'],
          'licenseUrl':'https://vrm.dev/licenses/1.0/','avatarPermission':'onlySeparatelyLicensedPerson',
          'allowRedistribution':False,'commercialUsage':'personalNonProfit','creditNotation':'required',
          'thirdPartyLicenses':'Original game assets retain their existing rights. Exporting does not grant additional rights.'}
    if author.strip():meta['authors'].append(author.strip())
    document.setdefault('extensions',{})['VRMC_vrm']={'specVersion':'1.0','meta':meta,'humanoid':{'humanBones':human}}
    used=document.setdefault('extensionsUsed',[])
    if 'VRMC_vrm' not in used:used.append('VRMC_vrm')
    document.pop('animations',None)
    for mesh in document.get('meshes',[]):
        for primitive in mesh.get('primitives',[]):primitive.get('attributes',{}).pop('TANGENT',None)
    report=validate(document,binary)
    return write_glb(document,binary),report
