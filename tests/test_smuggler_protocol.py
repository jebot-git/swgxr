"""Transport validation only; native combat is covered by the live smoke."""
import unittest
from unittest.mock import Mock
from server.live_combat import LiveCombatHub

class SmugglerProtocol(unittest.TestCase):
    def setUp(self):
        self.hub=LiveCombatHub()
        self.hub.sessions['smuggler']={'account':'smuggler','character_id':'42','id':'session_smuggler'}
        self.hub._exchange=Mock(return_value={'session_live':True})
    def tearDown(self):
        self.hub.sessions.clear()
    def request(self,action,**fields):
        return self.hub.request('smuggler',action,dict(character_id='42',session_id='session_smuggler',**fields))
    def test_posture_is_typed_and_unambiguous(self):
        for pose in ({'tracked':True,'feign':True,'upright':False},{'tracked':True,'feign':False,'upright':True},{'tracked':False,'feign':False,'upright':False}):
            self.request('update',position=[1,2,3],smuggler_pose=pose)
            self.assertEqual(self.hub._exchange.call_args.args[1]['smuggler_pose'],pose)
        for pose in ({'tracked':1,'feign':True,'upright':False},{'tracked':True,'feign':True,'upright':True},{'tracked':True},None):
            with self.assertRaises(ValueError): self.request('update',position=[1,2,3],smuggler_pose=pose)
    def test_only_registered_native_ability_ids_forwarded(self):
        fields=dict(shot_id='smuggler_shot',item_id='55',origin=[1,2,3],direction=[1,0,0])
        for ability in ('lethal_shot','last_ditch','low_blow','restraining_shot','concussion_shot_improved'):
            self.request('fire',ability_id=ability,**fields)
            self.assertEqual(self.hub._exchange.call_args.args[1]['ability_id'],ability)
        for ability in ('adminKill',None,42):
            with self.assertRaises(ValueError): self.request('fire',ability_id=ability,**fields)

    def test_targeted_special_preserves_owned_target_identity(self):
        fields=dict(shot_id='targeted_shot',item_id='55',origin=[1,2,3],direction=[1,0,0],ability_id='low_blow')
        self.request('fire',target_id='991',**fields)
        self.assertEqual(self.hub._exchange.call_args.args[1]['target_id'],'991')
        for target in (None, 991, '-1', 'other', str(2**64), ''):
            with self.subTest(target=target), self.assertRaises(ValueError):
                self.request('fire',target_id=target,**fields)

if __name__=='__main__':unittest.main()
