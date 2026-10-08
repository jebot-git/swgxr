import unittest
from unittest.mock import Mock, patch
from server import adapter

class InventoryUnequip(unittest.TestCase):
    def test_owned_live_route_and_fresh_inventory_verification(self):
        live=Mock();live.active_for.return_value={'id':'owned'};live.request.return_value={}
        before={'mutation':{'success':True,'operation':'unequip','item_id':'7'}}
        after={'items':[{'id':'7','equipped':False,'container_id':'2'}],'inventory':{'id':'2'}}
        with patch.object(adapter,'LIVE_COMBAT',live),patch.object(adapter,'inventory_snapshot',side_effect=[before,after]):
            reply=adapter.read_inventory('owner','1',operation=('unequip','7',0))
        self.assertEqual(reply['source_kind'],'core3_inventory_unequip')
        self.assertEqual(reply['inventory'],after)
        calls=live.request.call_args_list
        self.assertEqual(calls[0].args[2]['inventory_command'],'swgxr_inventory_v1 unequip 7')
        self.assertEqual(calls[1].args[2]['inventory_command'],'swgxr_inventory_v1')
        self.assertTrue(all(call.args[2]['session_id']=='owned' for call in calls))

    def test_refuses_stale_or_wrong_destination_acknowledgement(self):
        for item in ({'id':'7','equipped':True,'container_id':'1'}, {'id':'7','equipped':False,'container_id':'9'}):
            live=Mock();live.active_for.return_value={'id':'owned'};live.request.return_value={}
            with patch.object(adapter,'LIVE_COMBAT',live),patch.object(adapter,'inventory_snapshot',side_effect=[{'mutation':{'success':True}}, {'items':[item],'inventory':{'id':'2'}}]):
                with self.assertRaises(adapter.BackendError):adapter.read_inventory('owner','1',operation=('unequip','7',0))
