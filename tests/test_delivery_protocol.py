"""Native mission handoff boundary and datapad presentation contract."""
import copy
import unittest
from unittest.mock import patch
from server.services_protocol import command, snapshot


class DeliveryProtocol(unittest.TestCase):
    def body(self, **values):
        return dict(npc_id='100',mission_id='200',parcel_id='300',
                    request_id='delivery_request_001',**values)

    def native(self):
        return {'source_kind':'core3_services','character_id':'1','mutation':{'success':True},
                'delivery_contacts':[{'id':'100','kind':'delivery','mission_id':'200',
                    'name':'Giver','mission_name':'@mission/title:delivery','dialogue':'@mission/text:collect'}],
                'parcels':[{'id':'300','mission_id':'200','receiver_id':'101','stage':'deliver',
                    'mission_kind':'crafting','template':'object/tangible/mission/quest_item/power_regulator.iff',
                    'client_crc':42,'customization_hex':'','name_table':'mission/items','name_key':'regulator'}]}

    def test_open_is_read_only_and_confirm_requires_stable_receipt(self):
        request={'npc_id':'100','mission_id':'200'}
        self.assertEqual(command('delivery_open',request),dict(request,action='delivery_open'))
        for action in ('delivery_pickup','delivery_complete'):
            with self.assertRaises(ValueError):command(action,request)
            accepted=command(action,self.body())
            self.assertEqual(accepted['request_id'],'delivery_request_001')
            self.assertNotIn('terminal_id',accepted)

    def test_handoff_requires_specific_original_npc_mission_and_parcel(self):
        for field in ('npc_id','mission_id','parcel_id'):
            for value in ('', '0', '-1',str(2**64),17,True):
                payload=self.body();payload[field]=value
                with self.subTest(field=field,value=value),self.assertRaises(ValueError):
                    command('delivery_complete',payload)
        request=command('delivery_complete',self.body(credits=999999,success=True,stage='complete'))
        self.assertTrue({'credits','success','stage'}.isdisjoint(request))

    def test_original_cell_and_position_validation_is_shared(self):
        for values in ({'position':[1,float('nan'),2]}, {'building_id':'0','cell_index':2}):
            with self.assertRaises(ValueError):command('delivery_pickup',self.body(**values))

    @patch('server.services_protocol.template_label',return_value=('Source item','Source description'))
    @patch('server.services_protocol.template_names',return_value={42:'object/tangible/mission/quest_item/shared_power_regulator.iff'})
    @patch('server.services_protocol.display',side_effect=lambda table,key,fallback='':f'{table}/{key}' if table and key else fallback)
    def test_datapad_entry_references_native_item_and_preserves_crafting_identity(self,*_):
        raw=self.native();before=copy.deepcopy(raw)
        response=snapshot(raw,'1')
        parcel=response['state']['parcels'][0]
        self.assertEqual(parcel['id'],'300')
        self.assertEqual(parcel['attributes']['mission_id'],'200')
        self.assertTrue(parcel['attributes']['native_inventory_object'])
        self.assertEqual(parcel['mission_kind'],'crafting')
        self.assertEqual((parcel['category'],parcel['type']),('data','mission_parcel'))
        self.assertFalse(parcel['deletable'])
        self.assertEqual(parcel['name'],'mission/items/regulator')
        self.assertEqual(response['state']['delivery_contacts'][0]['dialogue'],'mission/text/collect')
        self.assertEqual(raw,before)

    def test_foreign_unbounded_or_unidentified_native_entries_rejected(self):
        raw=self.native()
        with self.assertRaises(ValueError):snapshot(raw,'2')
        for key,limit in (('delivery_contacts',32),('parcels',16)):
            invalid=self.native();invalid[key]=invalid[key]*(limit+1)
            with self.assertRaises(ValueError):snapshot(invalid,'1')
        invalid=self.native();invalid['parcels'][0]['mission_id']=''
        with self.assertRaises(ValueError):snapshot(invalid,'1')

    def test_native_rejection_cannot_become_local_success(self):
        raw=self.native();raw['parcels']=[]
        raw['mutation']={'success':False,'error':'parcel_required','request_id':'delivery_request_001'}
        response=snapshot(raw,'1')
        self.assertFalse(response['ok'])
        self.assertEqual(response['mutation']['error'],'parcel_required')
        self.assertEqual(response['state']['parcels'],[])


if __name__=='__main__':unittest.main()
