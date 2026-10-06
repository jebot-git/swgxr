import math
import json,re
from pathlib import Path
import unittest
from unittest.mock import patch
from server.services_protocol import command, snapshot, MUTATIONS
from server.remote_gateway import POST

class HarvesterProtocolTests(unittest.TestCase):
    def request(self, action, **fields):
        return command('house_harvester_'+action,dict(structure_id='123',request_id='harvester-request-1',**fields))
    def test_original_harvesting_structure_geometry_coverage(self):
        root=Path(__file__).resolve().parents[1]
        catalog=json.loads((root/'runtime/assets/housing/catalog.json').read_text())
        scripts=root/'vendor/Core3/MMOCoreORB/bin/scripts/object/tangible/deed'
        templates={m for kind in ('harvester_deed','generator_deed') for path in (scripts/kind).glob('*.lua') for m in re.findall(r'generatedObjectTemplate\s*=\s*"([^"]+)"',path.read_text())}
        self.assertEqual(len(templates),20)
        self.assertTrue(templates<=catalog['structures'].keys())
        for template in templates:
            model=json.loads((root/'runtime/assets/housing'/catalog['structures'][template]['path']).read_text())
            self.assertTrue(model['instances']);self.assertTrue(model['meshes']);self.assertTrue(model['provenance'])

    def test_routes_and_read_only_status(self):
        for action in ('status','select','active','power','deposit','collect','recover'):
            self.assertIn('/services/house_harvester_'+action,POST)
        self.assertNotIn('house_harvester_status',MUTATIONS)
        self.assertEqual(command('house_harvester_status',{'structure_id':'123'}),{'action':'house_harvester_status','structure_id':'123'})
    def test_mutations_need_receipts_and_never_trust_output_or_permission(self):
        with self.assertRaises(ValueError):command('house_harvester_deposit',{'structure_id':'123','amount':10})
        result=self.request('select',resource_id='444',density=1,owner=True,rate=5000)
        for key in ('density','owner','rate'):self.assertNotIn(key,result)
    def test_identity_validation(self):
        for action,field in [('power','item_id'),('select','resource_id')]:
            for value in (None,False,123,'0','-1','١٢',str(2**64)):
                with self.subTest(action=action,value=value),self.assertRaises(ValueError):self.request(action,**{field:value})
    def test_money_and_quantity_bounds(self):
        for action,key in [('deposit','amount'),('collect','quantity')]:
            for value in (None,0,-1,True,1.0,100000001):
                with self.subTest(action=action,value=value),self.assertRaises(ValueError):self.request(action,resource_id='444',**{key:value})
        self.assertEqual(self.request('collect',resource_id='444',quantity=100)['quantity'],100)
    def test_both_recovery_hands_required(self):
        for right in (None,[0,0],[math.nan,1,0],[True,1,0]):
            with self.assertRaises(ValueError):self.request('recover',left_hand=[0,1,0],right_hand=right)
        self.assertEqual(self.request('recover',left_hand=[0,1,0],right_hand=[1,1,0])['right_hand'],[1,1,0])
    def test_switch_is_binary(self):
        for value in (None,1,'true'):
            with self.assertRaises(ValueError):self.request('active',active=value)
        self.assertFalse(self.request('active',active=False)['active'])
    def test_datapad_only_references_actual_owned_inventory(self):
        raw={'source_kind':'core3_services','character_id':'42','housing':{'deeds':[{'id':'1'},{'id':'2'}]},'inventory':{'source_kind':'core3_inventory','character_id':'42','items':[{'id':'1','template':'deed','structure_template':'harvester','name':'Harvester'}]}}
        with patch('server.services_protocol.inventory_snapshot',lambda value,oid:value['variables']['inventory']):out=snapshot(raw,'42')
        rows=out['state']['housing']['deeds'];self.assertEqual(len(rows),1);self.assertEqual(rows[0]['id'],'1');self.assertEqual(rows[0]['type'],'harvesting_deed');self.assertFalse(rows[0]['deletable'])
        self.assertNotIn('type',raw['inventory']['items'][0])

if __name__=='__main__':unittest.main()
