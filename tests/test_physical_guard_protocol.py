import unittest
from server.physical_guard_protocol import pose

class GuardProtocolTests(unittest.TestCase):
    def example(self):
        return dict(mode='boxing', item_id='123', main='right', head=[100,2,200], forward=[0,0,1], left=[-.2,-.1,-.3], right=[.2,-.1,-.3], axis=[0,1,0])
    def test_valid_and_release(self):
        self.assertEqual(pose({'mode':'none'}),{'mode':'none'})
        for mode in ('boxing','parry'):
            value=self.example();value['mode']=mode
            self.assertEqual(pose(value),value)
            self.assertIsNot(pose(value)['left'],value['left'])
    def test_rejects_invalid_input(self):
        for key,value in [('mode','invulnerable'),('main','both'),('item_id','0'),('item_id',str(2**64)),('item_id',1),('head',[0,float('nan'),0]),('left',[True,0,0]),('right',[0,0]),('axis',[3,0,0]),('forward',[float('inf'),0,0])]:
            data=self.example();data[key]=value
            with self.subTest(key=key,value=value),self.assertRaises(ValueError):pose(data)
        for value in (None,[],{'mode':'none','damage_multiplier':0},dict(self.example(),damage_multiplier=0)):
            with self.assertRaises(ValueError):pose(value)
    def test_missing_fields(self):
        for key in self.example():
            value=self.example();del value[key]
            with self.assertRaises(ValueError):pose(value)

class GuardSessionTests(unittest.TestCase):
    def test_owned_update_forwards_validated_pose_only(self):
        import tempfile
        from pathlib import Path
        from unittest.mock import Mock
        from server.live_combat import LiveCombatHub, LiveConflict
        with tempfile.TemporaryDirectory() as directory:
            hub=LiveCombatHub()
            process=Mock();process.poll.return_value=None
            hub.sessions['owner']=dict(id='owned_session',account='owner',character_id='123',folder=Path(directory),options=Path(directory)/'options',process=process)
            hub._exchange=Mock(return_value={'session_live':True})
            data=dict(character_id='123',session_id='owned_session',position=[0,0,0],guard_pose=GuardProtocolTests().example())
            try:
                hub.request('owner','update',data)
                self.assertEqual(hub._exchange.call_args.args[1]['guard_pose'],data['guard_pose'])
                with self.assertRaises(LiveConflict):hub.request('owner','update',dict(data,session_id='foreign'))
                with self.assertRaises(ValueError):hub.request('owner','update',dict(data,guard_pose=dict(data['guard_pose'],damage_multiplier=0)))
                self.assertEqual(hub._exchange.call_count,1)
            finally:hub.close()
