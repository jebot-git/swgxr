import unittest
from unittest.mock import patch
from server.weapon_protocol import owned, weapon_snapshots, crc
from server.adapter import delete_datapad_entry
from tools.server.combat_protocol_smoke import fixture, numbers, pack


class WeaponProtocolTests(unittest.TestCase):
    def setUp(self):
        self.objects = {'o2':{'parentId':'1'}, 'o3':{'parentId':'2','type':0x5745414F,
                        'templateCrc':crc('object/weapon/ranged/pistol/shared_pistol_cdef.iff')}}
        # Owner observations are required before translating any item profile.
        for oid in ('1', '9'):
            player = fixture()[0]
            player['baseline1'] = (bytes(8) + numbers([1000,300,300]*3) + pack('II',0,0)).hex()
            player['baseline4'] = (bytes(8) + numbers([]) + pack('II',0,0)).hex()
            self.objects['o'+oid] = player
        self.result = {'variables':{'weapons':{'complete':True},'replication':{'objects':self.objects},
                                    'weaponAttributes':{'o3':{}}}}

    def test_owned_nested_and_cycle(self):
        self.assertTrue(owned(self.objects['o3'],self.objects,'1'))
        self.assertFalse(owned(self.objects['o3'],self.objects,'9'))
        self.objects['o2']['parentId']='3'
        self.assertFalse(owned(self.objects['o3'],self.objects,'1'))

    def test_missing_supported_server_profile_is_not_synthetic_fallback(self):
        with self.assertRaisesRegex(ValueError,'rebuild'): weapon_snapshots(self.result,'1')

    def test_balance_mismatch_rejected(self):
        self.result['variables']['weaponAttributes']['o3']={'swgxr.version':'1','swgxr.balance':'old'}
        with self.assertRaisesRegex(ValueError,'revision mismatch'): weapon_snapshots(self.result,'1')

    def test_missing_reply_rejected(self):
        self.result['variables']['weaponAttributes']={}
        with self.assertRaisesRegex(ValueError,'Missing'): weapon_snapshots(self.result,'1')

    def test_foreign_item_is_excluded(self):
        with patch('server.weapon_protocol.unarmed_snapshot',return_value={'character_id':'9'}):
            self.assertEqual(weapon_snapshots(self.result,'9')['weapons'],[])

    def test_missing_protocol_rejected(self):
        self.result['variables']['weapons']['complete']=False
        with self.assertRaises(ValueError): weapon_snapshots(self.result,'1')

    def test_protected_datapad_never_sends_destroy(self):
        with patch('server.adapter.read_datapad',return_value={'entries':[{'id':'3','deletable':False}]}), patch('server.adapter.invoke') as invoke:
            with self.assertRaises(ValueError): delete_datapad_entry('fixture',{'character_id':'1','entry_id':'3','deletable':True})
            invoke.assert_not_called()

    def test_unowned_datapad_never_sends_destroy(self):
        with patch('server.adapter.read_datapad',return_value={'entries':[]}), patch('server.adapter.invoke') as invoke:
            with self.assertRaises(ValueError): delete_datapad_entry('fixture',{'character_id':'1','entry_id':'3'})
            invoke.assert_not_called()

if __name__=='__main__': unittest.main()
