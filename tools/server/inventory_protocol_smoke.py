#!/usr/bin/env python3
"""Inventory decoder trust boundaries without pretending synthetic data is Core3."""
import sys
import unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from server.inventory_protocol import inventory_snapshot

class InventoryProtocol(unittest.TestCase):
    def fixture(self):
        item={'id':'12','container_id':'11','template':'object/test.iff','client_crc':0,'custom_name':'Fixture','name_table':'','name_key':'','quantity':1,'use_count':12,'equipped':False,'description':'','stack_kind':'none','split_supported':False}
        return {'variables':{'inventory':{'source_kind':'core3_inventory','character_id':'10','inventory':{'id':'11','capacity':80,'occupied':1},'containers':[{'id':'11','capacity':80,'occupied':1,'direct_count':1,'depth':0,'item_ids':['12']}],'items':[item],'equipped_backpack':None},'weaponAttributes':{'o12':{'condition':'10/10'}}}}
    def decode(self,data):
        with patch('server.inventory_protocol.template_names',return_value={}), patch('server.inventory_protocol.template_label',return_value=('Fallback',{})):
            return inventory_snapshot(data,'10')
    def test_charges_are_not_quantity(self):
        item=self.decode(self.fixture())['items'][0]
        self.assertEqual((item['quantity'],item['use_count'],item['split_supported']),(1,12,False))
    def test_missing_attributes(self):
        data=self.fixture(); data['variables']['weaponAttributes']={}
        with self.assertRaises(ValueError):self.decode(data)
    def test_wrong_owner(self):
        data=self.fixture();data['variables']['inventory']['character_id']='100'
        with self.assertRaises(ValueError):self.decode(data)
    def test_missing_child(self):
        data=self.fixture();data['variables']['inventory']['containers'][0]['item_ids']=['13']
        with self.assertRaises(ValueError):self.decode(data)
    def test_outside_hierarchy(self):
        data=self.fixture();data['variables']['inventory']['items'][0]['container_id']='90'
        with self.assertRaises(ValueError):self.decode(data)
    def test_truncation_error(self):
        data=self.fixture();data['variables']['inventory']['error']='Inventory bounds exceeded'
        with self.assertRaises(ValueError):self.decode(data)

if __name__=='__main__':unittest.main()
