import copy
import unittest
from unittest.mock import patch, Mock
from server import adapter
from server.crafting_protocol import crafting_snapshot
from server.scout_protocol import command, snapshot

class Core5BackendTests(unittest.TestCase):
    def test_native_timeout_is_uncertain_and_keeps_connection(self):
        with self.assertRaises(adapter.NativeReplyTimeout) as caught:
            adapter.check_live_error({'error_code': 'native_response_timeout', 'session_live': True})
        response = caught.exception.response()
        self.assertTrue(response['session_live'])
        self.assertTrue(response['request_timeout'])
        self.assertTrue(response['mutation_started'])
        self.assertFalse(response['ok'])
        self.assertNotIn('confirmed_rejection', response)

    def test_crafting_original_labels_and_native_indices(self):
        raw={'variables':{'crafting':{'character_id':'1','state':{
            'source_kind':'core3_crafting','character_id':'1','tool_tabs':[1,64],
            'tool_template':'original_tool','max_complexity':20,
            'schematics':[{'index':37,'id':'9','name':'Weapon','category_id':'1',
                          'tool_compatible':True,'description':'@craft_weapon_ingredients_d:barrel','slots':[]}]
        }}}}
        def original(table,key,fallback):
            return {('craft_types','weapon'):'Original weapon category',
                    ('craft_weapon_ingredients_d','barrel'):'Original barrel description'}.get((table,key),fallback)
        with patch('server.crafting_protocol.display',side_effect=original),patch('server.crafting_protocol.template_names',return_value={}):
            result=crafting_snapshot(raw,'1')['state']
        row=result['schematics'][0]
        self.assertEqual(row['index'],37)
        self.assertEqual(row['category'],'Original weapon category')
        self.assertEqual(row['description'],'Original barrel description')
        self.assertTrue(row['tool_compatible'])
        self.assertEqual(result['tool_tabs'],[1,64])
        self.assertNotIn('category',raw['variables']['crafting']['state']['schematics'][0])

    def test_inspection_reads_only_requested_native_attributes(self):
        self.assertEqual(command('inspect',{'position':[0,0,0],'target_id':'9'})['target_id'],'9')
        raw={'source_kind':'core3_scout','character_id':'1','state':{'character_id':'1','inventory':{}},
             'mutation':{'inspection':{'id':'9','name':'@mob:beast'}}}
        attrs={'o9':{'aggro':'yes','swgxr.private':'hidden'},'o10':{'killer':'yes'}}
        with patch('server.scout_protocol.inventory_snapshot',return_value={}),patch('server.scout_protocol.display',side_effect=lambda t,k,f:f):
            result=snapshot(raw,'1',attrs)['mutation']['inspection']
        self.assertEqual(result['attributes'],[{'key':'aggro','name':'aggro','value':'yes'}])
        with self.assertRaises(ValueError):snapshot(raw,'1',{})
        for target in ('0','-1',True,str(2**64)):
            with self.assertRaises(ValueError):command('inspect',{'position':[0,0,0],'target_id':target})

    def test_service_movement_failure_preserves_owned_correction(self):
        envelope={'backend':'core3','source_kind':'core3_live_combat','session_live':True,
                  'session_id':'owned','character_id':'1','sequence':7,
                  'error_code':'native_movement_speed_rejected',
                  'mutation':{'movement_accepted':False},'snapshot':{'player':{'position':[1,2,3]}}}
        live=Mock();live.active_for.return_value={'id':'owned'};live.request.return_value=envelope
        with patch.object(adapter,'LIVE_COMBAT',live),patch.object(adapter,'services_command',return_value={'action':'status'}):
            with self.assertRaises(adapter.NativeMovementRejected) as caught:
                adapter.services_request('owner','1','status',{})
        response=caught.exception.response()
        self.assertFalse(response['ok'])
        self.assertIs(response['live_response'],envelope)
        self.assertEqual(response['live_response']['sequence'],7)
        with self.assertRaises(ValueError):adapter.check_live_error({'error_code':'native_inventory_overloaded'})
        adapter.check_live_error({'snapshot':{}})

    def test_gameplay_movement_failure_preserves_owned_correction(self):
        envelope = {'character_id': '1', 'session_id': 'owned', 'sequence': 12,
                    'session_live': True, 'error_code': 'native_movement_speed_rejected',
                    'mutation': {'movement_accepted': False, 'success': False},
                    'snapshot': {'player': {'position': [1, 2, 3]}}}
        live = Mock()
        live.active_for.return_value = {'id': 'owned', 'purpose': 'gameplay'}
        live.request.return_value = envelope
        with patch.object(adapter, 'LIVE_COMBAT', live):
            with self.assertRaises(adapter.NativeMovementRejected) as caught:
                adapter.gameplay_session('owner', {'character_id': '1', 'position': [501, 2, 3]})
        self.assertIs(caught.exception.response()['live_response'], envelope)

if __name__=='__main__':unittest.main()
