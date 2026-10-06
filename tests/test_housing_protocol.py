import math,unittest
from server.services_protocol import command,MUTATIONS
from server.housing_protocol import ACTIONS
from server.remote_gateway import POST
from server.services_presence import PresenceHub
class HousingProtocolTests(unittest.TestCase):
 def req(self,action,**data):return command('house_'+action,dict(request_id='housing-test-001',**data))
 def test_preview_is_read_only_and_routes_are_authenticated(self):
  for action in ACTIONS:self.assertIn('/services/'+action,POST)
  self.assertNotIn('house_preview',MUTATIONS);self.assertNotIn('house_status',MUTATIONS)
  self.assertEqual(command('house_preview',dict(deed_id='42',placement_position=[1,2,3],rotation=2))['rotation'],2)
 def test_placement_inputs_do_not_override_core3_rules(self):
  out=self.req('place',deed_id='42',placement_position=[1,0,3],rotation=1,lots=0,valid=True,build_time=0)
  self.assertNotIn('lots',out);self.assertNotIn('valid',out);self.assertNotIn('build_time',out)
  for value in [-1,4,1.0,True]:
   with self.assertRaises(ValueError):self.req('preview',deed_id='42',placement_position=[0,0,0],rotation=value)
  for value in [None,42,'0','١٢',str(2**64)]:
   with self.assertRaises(ValueError):self.req('place',deed_id=value,placement_position=[0,0,0],rotation=0)
 def test_furniture_pose_validation(self):
  good=dict(item_id='44',placement_position=[0,1,0],local_quaternion=[0,0,0,1],suspended=True)
  self.assertTrue(self.req('drop',**good)['suspended'])
  for change in [dict(suspended=1),dict(local_quaternion=[0,0,0,0]),dict(placement_position=[0,math.nan,0]),dict(local_quaternion=[math.inf,0,0,1])]:
   with self.assertRaises(ValueError):self.req('drop',**dict(good,**change))
  with self.assertRaises(ValueError):self.req('recover',item_id='44',left_hand=[0,0,0])
 def test_permission_and_upkeep_bounds(self):
  for amount in [0,-1,True,100000001]:
   with self.assertRaises(ValueError):self.req('deposit',terminal_id='42',amount=amount)
  for perm,op in [('OWNER','add'),('ENTRY','toggle')]:
   with self.assertRaises(ValueError):self.req('permission_arm',terminal_id='42',permission_list=perm,permission_action=op)
  self.assertEqual(self.req('permission_arm',terminal_id='42',permission_list='ADMIN',permission_action='remove')['permission_action'],'remove')
class HousingHandshakeTests(unittest.TestCase):
 def setUp(self):
  self.now=100.;self.hub=PresenceHub(lambda:self.now);self.seq={'1':0,'2':0};self.tokens={}
  for oid in self.seq:self.tokens[oid]=self.hub.register('owner'+oid,oid,dict(position=[0,0,0],cell_id='55',building_id='50',cell_index=1))['token']
 def pose(self,oid,grip=True):
  self.seq[oid]+=1
  return self.hub.update('owner'+oid,oid,self.tokens[oid],dict(sequence=self.seq[oid],position=[0,0,0],hand=dict(position=[0,1,0],tracked=True,grip=grip),wallet_held=False))
 def arm(self,key='house-arm-0001'):
  self.hub.arm_house_permission('owner1','1',dict(arm_id=key,structure_id='50',permission_list='ENTRY',permission_action='add'))
 def shake(self):
  self.pose('1');self.pose('2');self.now+=.3;self.pose('2');return self.pose('1')
 def authorize(self,key='house-apply-0001',arm='house-arm-0001'):
  return self.hub.authorize_house_permission('owner1','1','2',key,arm)
 def test_empty_hand_handshake_and_one_use(self):
  self.arm();reply=self.shake();self.assertTrue(reply['peers'][0]['house_permission_ready']);self.assertFalse(reply['peers'][0]['handshake_authorized'])
  self.assertEqual(self.authorize(),self.authorize())
  with self.assertRaises(ValueError):self.authorize('house-apply-0002')
 def test_selection_required_and_new_selection_invalidates_proof(self):
  self.shake()
  with self.assertRaises(ValueError):self.authorize()
  self.arm();self.shake();self.arm('house-arm-0002')
  with self.assertRaises(ValueError):self.authorize(arm='house-arm-0002')
 def test_minute_expiry_and_replay_cannot_extend(self):
  self.arm();self.now+=59;self.arm();self.shake();self.authorize();self.now+=1
  self.pose('1');self.pose('2')
  with self.assertRaises(ValueError):self.authorize()
 def test_owner_can_leave_private_house_before_handshake(self):
  self.arm()
  for oid in ('1','2'):
   self.hub.register('owner'+oid,oid,dict(position=[0,0,0],cell_id='0',building_id='0',cell_index=0))
  self.shake();self.assertEqual(self.authorize()['target_cell_index'],0)
 def test_cell_change_invalidates_and_tracking_must_be_fresh(self):
  self.arm();self.shake();self.now+=1.1
  with self.assertRaises(ValueError):self.authorize()
  self.pose('1');self.pose('2');self.hub.register('owner1','1',dict(position=[0,0,0],cell_id='99'))
  with self.assertRaises(ValueError):self.authorize()
if __name__=='__main__':unittest.main()
