import unittest
from server.services_presence import PresenceHub
from server.entertainer_protocol import command
from unittest.mock import patch

class PartyPresenceTests(unittest.TestCase):
 def setUp(self):
  self.now=100.;self.hub=PresenceHub(lambda:self.now);self.seq={'1':0,'2':0};self.tokens={}
  for oid in self.seq:self.tokens[oid]=self.hub.register('account'+oid,oid,{'position':[0,0,0],'zone':'tatooine','cell_id':'0'})['token']
 def pose(self,oid,x=0,**hand):
  self.seq[oid]+=1
  h=dict(position=[x,1,0],tracked=True,fist=True,free=True);h.update(hand)
  return self.hub.update('account'+oid,oid,self.tokens[oid],dict(sequence=self.seq[oid],position=[0,0,0],wallet_held=False,hand=dict(position=[0,1,0],tracked=True,grip=True),hands={'left' if oid=='1' else 'right':h}))
 def ready(self):
  self.pose('1',-.5);self.pose('2',.5);self.pose('1');self.pose('2');self.now+=.11
  out=self.pose('1');self.assertTrue(out['peers'][0]['group_bump_ready']);return out['peers'][0]['group_bump_id']
 def authorize(self,key,request='bump_request_001',actor='1',target='2'):
  return self.hub.authorize_group_bump('account'+actor,actor,target,request,key)
 def test_either_hand_mutual_proof_and_global_consumption(self):
  key=self.ready();self.assertEqual(len(key),24);self.assertFalse(self.authorize(key)['receipt_only']);self.assertTrue(self.authorize(key)['receipt_only'])
  self.assertEqual(self.authorize(key),self.authorize(key))
  with self.assertRaises(ValueError):self.authorize(key,'other_request')
  with self.assertRaises(ValueError):self.authorize(key,'bump_request_001','2','1')
 def test_initial_stationary_overlap_never_arms(self):
  self.pose('1');self.pose('2');self.now+=.2
  self.assertFalse(self.pose('1')['peers'][0]['group_bump_ready'])
 def test_wallet_handshake_cannot_authorize_party(self):
  with self.assertRaises(ValueError):self.authorize('a'*24)
  self.assertFalse(self.hub.bump_proofs)
 def test_no_rearm_until_separation_or_release(self):
  key=self.ready();self.authorize(key);self.now+=.2
  self.pose('2');self.assertFalse(self.pose('1')['peers'][0]['group_bump_ready'])
  self.pose('1',fist=False);self.pose('1');self.pose('2');self.now+=.11
  out=self.pose('1')['peers'][0];self.assertTrue(out['group_bump_ready']);self.assertNotEqual(out['group_bump_id'],key)
 def test_occupied_or_untracked_fist_invalidates_unconsumed_proof(self):
  for change in ({'free':False},{'tracked':False}):
   with self.subTest(change=change):
    self.setUp();key=self.ready();self.pose('2',**change)
    with self.assertRaises(ValueError):self.authorize(key)
    self.pose('2');self.now+=.15;self.assertFalse(self.pose('1')['peers'][0]['group_bump_ready'])
 def test_stale_tracking_requires_new_observed_separation(self):
  self.pose('1',-.5);self.pose('2',.5);self.now+=2
  self.pose('1');self.pose('2');self.now+=.2
  self.assertFalse(self.pose('1')['peers'][0]['group_bump_ready'])
 def test_consumed_same_receipt_can_retry_after_leave_distance_or_tracking_loss(self):
  key=self.ready();self.authorize(key);self.now+=2;self.pose('1',tracked=False)
  self.assertEqual(self.authorize(key)['group_bump_id'],key)
  with self.assertRaises(ValueError):self.authorize(key,'rejoin_new_key')
 def test_cell_transition_invalidates_unconsumed_proof(self):
  key=self.ready();self.hub.register('account2','2',{'position':[0,0,0],'zone':'tatooine','cell_id':'99'})
  with self.assertRaises(ValueError):self.authorize(key)
 def test_dwell_and_validated_fields(self):
  self.pose('1',-.5);self.pose('2',.5);self.pose('1');self.pose('2');self.now+=.05
  self.assertFalse(self.pose('1')['peers'][0]['group_bump_ready'])
  with self.assertRaises(ValueError):self.pose('1',free=1)
  with self.assertRaises(ValueError):self.pose('1',position=[0,5,0])
 def test_group_command_drops_client_authorization_and_requires_server_id(self):
  args=dict(request_id='bump_request',target_id='2',group_bump_id='a'*24,group_bump_authorized=True)
  out=command('group_bump',args);self.assertNotIn('group_bump_authorized',out)
  for key in ('', 'a'*25, '../proof'):
   with self.assertRaises(ValueError):command('group_bump',dict(args,group_bump_id=key))
 def test_adapter_requires_proof_before_native_mutation(self):
  from server import adapter
  data=dict(request_id='bump_request',target_id='2',group_bump_id='a'*24)
  with patch.object(adapter.LIVE_COMBAT,'active_for',return_value={'id':'session'}),patch.object(adapter.LIVE_COMBAT,'request') as native,patch.object(adapter.SERVICES_PRESENCE,'authorize_group_bump',side_effect=ValueError('proof required')):
   with self.assertRaises(ValueError):adapter.entertainer_request('account1','1','group_bump',data)
   native.assert_not_called()
 def test_adapter_passes_only_trusted_receipt_only_marker(self):
  from server import adapter
  data=dict(request_id='bump_request',target_id='2',group_bump_id='a'*24,group_bump_receipt_only=False)
  reply={'mutation':{'source_kind':'core3_entertainer','character_id':'1','state':{'character_id':'1'},'mutation':{'success':True}}}
  with patch.object(adapter.LIVE_COMBAT,'active_for',return_value={'id':'session'}),patch.object(adapter.LIVE_COMBAT,'request',return_value=reply) as native,patch.object(adapter.SERVICES_PRESENCE,'authorize_group_bump',return_value={'group_bump_id':'a'*24,'receipt_only':True}),patch.object(adapter.PERFORMANCE_HUB,'observe_native'):
   adapter.entertainer_request('account1','1','group_bump',data)
   command=native.call_args.args[2]['entertainer']
   self.assertTrue(command['group_bump_authorized']);self.assertTrue(command['group_bump_receipt_only'])

if __name__=='__main__':unittest.main()
