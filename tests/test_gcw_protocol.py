import unittest
from server.services_protocol import command,snapshot

class GcwProtocol(unittest.TestCase):
 def data(self,**kw):return dict(request_id='gcw_test_123',terminal_id='123',zone='tatooine',**kw)
 def test_join(self):self.assertEqual(command('recruiter_join',self.data())['terminal_id'],'123')
 def test_status(self):
  self.assertEqual(command('recruiter_status_toggle',self.data(expected_status=0))['expected_status'],0)
  for value in (True,2,-1,'0'):
   with self.assertRaises(ValueError):command('recruiter_status_toggle',self.data(expected_status=value))
 def test_promote(self):
  self.assertEqual(command('recruiter_promote',self.data(expected_rank=0))['expected_rank'],0)
  for rank in (-1,16,True,'0'):
   with self.assertRaises(ValueError):command('recruiter_promote',self.data(expected_rank=rank))
 def test_rewards(self):
  self.assertEqual(command('recruiter_purchase',self.data(reward_id='rebel:weaponsArmor:carbine_laser'))['reward_id'],'rebel:weaponsArmor:carbine_laser')
  for value in ('imperial:installations:hq','rebel:hirelings:soldier','../reward','rebel:furniture:chair;drop'):
   with self.assertRaises(ValueError):command('recruiter_purchase',self.data(reward_id=value))
 def test_fine(self):
  self.assertFalse(command('contraband_answer',self.data(scan_id='456',accept=False))['accept'])
  for fields in ({'accept':True},{'scan_id':'٤٥٦','accept':True},{'scan_id':'456','accept':1}):
   with self.assertRaises(ValueError):command('contraband_answer',self.data(**fields))
 def test_ids(self):
  for value in ('１２３','0',str(2**64),'3 OR 1'):
   d=self.data();d['terminal_id']=value
   with self.assertRaises(ValueError):command('recruiter_join',d)
 def test_snapshot(self):
  raw=dict(source_kind='core3_services',character_id='123',gcw=dict(pve_only=True,faction='rebel',status=1,scan=dict(active=True,id='9',answer_pending=True,fine=2000)),terminal=dict(kind='recruiter',id='10',recruiter_text='Source dialogue',rewards=[dict(id='rebel:furniture:x',eligible=False,reason='Not enough standing',cost_faction_points=200)]))
  out=snapshot(raw,'123');self.assertEqual(out['state']['gcw'],raw['gcw']);self.assertEqual(out['state']['terminal']['rewards'],raw['terminal']['rewards'])
