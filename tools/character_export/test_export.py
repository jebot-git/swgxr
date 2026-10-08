import copy
import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parent))
from vrm import BONES, PARENTS, REQUIRED, ExportError, make_vrm, read_glb, write_glb, validate
from export_character import normalize_snapshot, connection, request_json, NoRedirect, choose_character, publish


def fixture():
    names=[name for name in BONES if name in REQUIRED]
    indices={name:i for i,name in enumerate(names)}
    nodes=[{'name':BONES[name]} for name in names]
    for name in names:
        parent=PARENTS.get(name)
        while parent and parent not in indices:parent=PARENTS.get(parent)
        if parent:nodes[indices[parent]].setdefault('children',[]).append(indices[name])
    data=bytearray();views=[];accessors=[]
    def accessor(payload,count,kind,component):
        while len(data)%4:data.append(0)
        views.append({'buffer':0,'byteOffset':len(data),'byteLength':len(payload)})
        data.extend(payload);accessors.append({'bufferView':len(views)-1,'count':count,'componentType':component,'type':kind})
        return len(accessors)-1
    position=accessor(struct.pack('<9f',0,0,0,1,0,0,0,1,0),3,'VEC3',5126)
    joints=accessor(bytes(12),3,'VEC4',5121)
    weights=accessor(struct.pack('<12f',*[1,0,0,0]*3),3,'VEC4',5126)
    bind=accessor(struct.pack('<16f',1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1)*len(names),len(names),'MAT4',5126)
    nodes.append({'name':'Body','mesh':0,'skin':0})
    document={'asset':{'version':'2.0'},'buffers':[{'byteLength':len(data)}],'bufferViews':views,'accessors':accessors,
        'nodes':nodes,'scene':0,'scenes':[{'nodes':[indices['hips'],len(nodes)-1]}],
        'skins':[{'joints':list(range(len(names))),'inverseBindMatrices':bind}],
        'meshes':[{'primitives':[{'attributes':{'POSITION':position,'JOINTS_0':joints,'WEIGHTS_0':weights}}]}]}
    return document,bytes(data)

class VRMTests(unittest.TestCase):
    def test_self_contained_vrm_and_orientation(self):
        source,binary=fixture();data,report=make_vrm(write_glb(source,binary),'Test Avatar','Assembler')
        vrm,embedded=read_glb(data)
        self.assertEqual(embedded,binary)
        self.assertEqual(report['humanoid_bones'],15)
        self.assertNotIn('rotation',vrm['nodes'][-1])
        rotated,_=make_vrm(write_glb(source,binary),'Legacy',source_forward='-Z')
        self.assertEqual(read_glb(rotated)[0]['nodes'][-1]['rotation'],[0,1,0,0])
        self.assertEqual(vrm['extensions']['VRMC_vrm']['meta']['authors'][-1],'Assembler')
        self.assertFalse(vrm['extensions']['VRMC_vrm']['meta']['allowRedistribution'])
    def test_missing_bone_rejected(self):
        doc,binary=fixture();doc['nodes'][2]['name']='not_head'
        with self.assertRaisesRegex(ExportError,'required'):make_vrm(write_glb(doc,binary),'Test')
    def test_ambiguous_bone_rejected(self):
        doc,binary=fixture();doc['nodes'].append({'name':'root'})
        with self.assertRaisesRegex(ExportError,'Ambiguous'):make_vrm(write_glb(doc,binary),'Test')
    def test_unskinned_rejected(self):
        doc,binary=fixture();del doc['nodes'][-1]['skin']
        with self.assertRaisesRegex(ExportError,'skinned geometry'):make_vrm(write_glb(doc,binary),'Test')
    def test_invalid_weight_values_rejected(self):
        doc,binary=fixture();data=bytearray(binary)
        view=doc['bufferViews'][doc['accessors'][2]['bufferView']]
        struct.pack_into('<f',data,view['byteOffset'],float('nan'))
        with self.assertRaisesRegex(ExportError,'Skin weights'):make_vrm(write_glb(doc,bytes(data)),'Test')
    def test_out_of_range_vertex_joint_rejected(self):
        doc,binary=fixture();data=bytearray(binary)
        view=doc['bufferViews'][doc['accessors'][1]['bufferView']];data[view['byteOffset']]=255
        with self.assertRaisesRegex(ExportError,'nonexistent skin joint'):make_vrm(write_glb(doc,bytes(data)),'Test')
    def test_truncated_chunk_rejected(self):
        doc,binary=fixture()
        with self.assertRaises(ExportError):read_glb(write_glb(doc,binary)[:-1])
    def test_accessor_bounds_rejected(self):
        doc,binary=fixture();doc['accessors'][0]['count']=500
        with self.assertRaisesRegex(ExportError,'Accessor'):make_vrm(write_glb(doc,binary),'Test')
    def test_external_image_rejected(self):
        doc,binary=fixture();doc['images']=[{'uri':'local-secret.png'}]
        with self.assertRaisesRegex(ExportError,'External textures'):make_vrm(write_glb(doc,binary),'Test')
    def test_external_buffer_rejected(self):
        doc,binary=fixture();doc['buffers'][0]['uri']='body.bin'
        with self.assertRaisesRegex(ExportError,'embedded buffer'):make_vrm(write_glb(doc,binary),'Test')
    def test_cycle_rejected(self):
        doc,binary=fixture();doc['nodes'][0].setdefault('children',[]).append(0)
        with self.assertRaisesRegex(ExportError,'Cyclic'):make_vrm(write_glb(doc,binary),'Test')
    def test_invalid_humanoid_ancestry_rejected(self):
        doc,binary=fixture();data,_=make_vrm(write_glb(doc,binary),'Test');doc,binary=read_glb(data)
        doc['extensions']['VRMC_vrm']['humanoid']['humanBones']['leftHand']['node']=doc['extensions']['VRMC_vrm']['humanoid']['humanBones']['rightHand']['node']
        with self.assertRaisesRegex(ExportError,'share nodes'):validate(doc,binary)
    def test_positive_scales_required(self):
        doc,binary=fixture();doc['nodes'][0]['scale']=[1,0,1]
        with self.assertRaisesRegex(ExportError,'Nonpositive'):make_vrm(write_glb(doc,binary),'Test')
    def test_joint_weights_required(self):
        doc,binary=fixture();del doc['meshes'][0]['primitives'][0]['attributes']['WEIGHTS_0']
        with self.assertRaisesRegex(ExportError,'joint weights'):make_vrm(write_glb(doc,binary),'Test')

class PublishTests(unittest.TestCase):
    def test_raced_report_is_preserved_and_avatar_rolled_back(self):
        with tempfile.TemporaryDirectory() as directory:
            output=Path(directory)/'avatar.vrm';report=output.with_suffix('.vrm.json')
            report.write_text('existing report')
            with self.assertRaises(FileExistsError):publish(output,b'avatar',{},False)
            self.assertEqual(report.read_text(),'existing report');self.assertFalse(output.exists())
            self.assertEqual(len(list(Path(directory).iterdir())),1)
    def test_existing_avatar_is_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            output=Path(directory)/'avatar.vrm';output.write_bytes(b'old')
            with self.assertRaises(FileExistsError):publish(output,b'new',{},False)
            self.assertEqual(output.read_bytes(),b'old')
    def test_force_replaces_pair(self):
        with tempfile.TemporaryDirectory() as directory:
            output=Path(directory)/'avatar.vrm';output.write_bytes(b'old')
            publish(output,b'new',{'ok':True},True)
            self.assertEqual(output.read_bytes(),b'new')
            self.assertTrue(json.loads(output.with_suffix('.vrm.json').read_text())['ok'])

class InputTests(unittest.TestCase):
    def snapshot(self):return {'token':'never export','character':{'id':'42','name':'Native','appearance':{'race':'human_male','customization':{},'source':'core3_replication'},'equipment':[],'secret':'exclude'}}
    def test_sanitize_snapshot(self):
        value=normalize_snapshot(self.snapshot(),'42')
        self.assertNotIn('secret',json.dumps(value));self.assertNotIn('token',json.dumps(value))
        self.assertEqual(value['character']['equipment'],[])
    def test_no_invented_outfit(self):
        value=self.snapshot();del value['character']['equipment']
        with self.assertRaisesRegex(ExportError,'equipment array'):normalize_snapshot(value)
    def test_wrong_character_rejected(self):
        with self.assertRaisesRegex(ExportError,'different character'):normalize_snapshot(self.snapshot(),'99')
    def test_remote_http_rejected(self):
        with self.assertRaisesRegex(ExportError,'HTTPS'):connection('http://example.com','account','token')
    def test_remote_account_only_rejected(self):
        with self.assertRaisesRegex(ExportError,'token'):connection('https://example.com','account',None)
    def test_local_account_requires_identity(self):
        with self.assertRaisesRegex(ExportError,'account'):connection('http://127.0.0.1:18080',None,None)
    def test_token_only_in_header(self):
        base,headers=connection('https://example.com',None,'token')
        self.assertEqual(headers,{'Authorization':'Bearer token'});self.assertNotIn('token',base)
    def test_no_redirect_auth_leak(self):
        with self.assertRaisesRegex(ExportError,'redirect'):NoRedirect().redirect_request(None,None,302,'',{},'https://elsewhere.test')
    def test_url_userinfo_rejected(self):
        with self.assertRaises(ExportError):connection('https://user:secret@example.com',None,'token')

if __name__=='__main__':unittest.main()
