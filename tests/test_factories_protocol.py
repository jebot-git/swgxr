"""Factory API authority boundaries and native patch integration."""
import math
import unittest
from unittest.mock import patch
from server.services_protocol import command, snapshot, MUTATIONS
from server.remote_gateway import POST

ACTIONS=('status','blueprint','remove_blueprint','input','withdraw','collect','active','power','deposit','recover')

class FactoryProtocolTests(unittest.TestCase):
    def request(self,action,**fields):
        return command('house_factory_'+action,dict(structure_id='123',request_id='factory-request-1',**fields))

    def test_status_is_read_only_and_all_actions_are_authenticated_routes(self):
        for action in ACTIONS:self.assertIn('/services/house_factory_'+action,POST)
        self.assertNotIn('house_factory_status',MUTATIONS)
        self.assertEqual(command('house_factory_status',{'structure_id':'123'}),{'action':'house_factory_status','structure_id':'123'})
        for action in ACTIONS[1:]:self.assertIn('house_factory_'+action,MUTATIONS)

    def test_item_moves_require_native_ids_and_receipts(self):
        for action in ('blueprint','input','withdraw','collect','power'):
            with self.subTest(action=action):
                for value in (None,False,123,'0','-1','١٢',str(2**64)):
                    with self.assertRaises(ValueError):self.request(action,item_id=value)
                with self.assertRaises(ValueError):command('house_factory_'+action,{'structure_id':'123','item_id':'456'})
                out=self.request(action,item_id='456',quantity=999,owner=True,output=[{'id':'fake'}],blueprint={'id':'fake'},power=1000)
                self.assertEqual(set(out),{'action','structure_id','item_id','request_id'})

    def test_structure_identity_is_mandatory_even_for_read_only(self):
        for value in (None,False,123,'0','-1','١٢',str(2**64)):
            with self.assertRaises(ValueError):command('house_factory_status',{'structure_id':value})

    def test_blueprint_removal_does_not_accept_replacement_or_forged_item(self):
        out=self.request('remove_blueprint',item_id='999',blueprint={'id':'999'})
        self.assertEqual(set(out),{'action','structure_id','request_id'})

    def test_upkeep_and_active_types_are_strict(self):
        for value in (None,0,-1,True,1.0,100000001):
            with self.assertRaises(ValueError):self.request('deposit',amount=value)
        for value in (None,1,'true'):
            with self.assertRaises(ValueError):self.request('active',active=value)
        self.assertEqual(self.request('deposit',amount=100)['amount'],100)
        self.assertFalse(self.request('active',active=False)['active'])

    def test_recovery_needs_two_finite_hands(self):
        for value in (None,[0,1],[math.nan,1,0],[True,1,0],[8193,1,0]):
            with self.assertRaises(ValueError):self.request('recover',left_hand=[0,1,0],right_hand=value)
        self.assertEqual(self.request('recover',left_hand=[0,1,0],right_hand=[1,1,0])['right_hand'],[1,1,0])

    def test_factory_deed_normalization_requires_actual_owned_inventory(self):
        item={'id':'1','template':'deed','structure_template':'object/installation/manufacture/food_factory.iff','name':'Food factory'}
        raw={'source_kind':'core3_services','character_id':'42','housing':{'deeds':[{'id':'1'},{'id':'2'}]},'inventory':{'source_kind':'core3_inventory','character_id':'42','items':[item]}}
        with patch('server.services_protocol.inventory_snapshot',lambda value,oid:value['variables']['inventory']):out=snapshot(raw,'42')
        rows=out['state']['housing']['deeds'];self.assertEqual(len(rows),1);self.assertEqual(rows[0]['type'],'factory_deed');self.assertFalse(rows[0]['deletable'])
        self.assertNotIn('type',item)

if __name__=='__main__':unittest.main()
