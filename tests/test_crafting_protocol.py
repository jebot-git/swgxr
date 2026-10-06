import unittest
from server.crafting_protocol import command
class CraftingValidation(unittest.TestCase):
 def setUp(self):self.base={'request_id':'request-123','tool_id':'123','session_id':'session-123','position':[3600,5,-4780]}
 def test_identity_and_position(self):
  self.assertEqual(command('open',self.base)['tool_id'],'123')
  for changes in [{'tool_id':'-1'},{'tool_id':123},{'position':[float('nan'),0,0]},{'position':[0,3000,0]},{'request_id':'short'}]:
   with self.assertRaises(ValueError):command('open',dict(self.base,**changes))
 def test_cancellation_requires_only_identity(self):
  result=command('cancel',{'request_id':'request-123','session_id':'session-123'})
  self.assertNotIn('position',result);self.assertNotIn('tool_id',result)
 def test_allocations(self):
  self.assertEqual(command('assemble',dict(self.base,allocations=[['123'],[]]))['allocations'],[['123'],[]])
  for value in [None,{},[[True]],[['0']],[[str(2**64)]]]:
   with self.assertRaises(ValueError):command('assemble',dict(self.base,allocations=value))
 def test_integer_points_and_colors(self):
  self.assertEqual(command('finish',dict(self.base,points=[0,2],colors=[17]))['points'],[0,2])
  for key,values in [('points',[True]),('points',[-1]),('points',[11]),('colors',[256]),('colors',[1.5])]:
   with self.assertRaises(ValueError):command('finish',dict(self.base,**{key:values}))
 def test_blueprint_output_and_limit(self):
  self.assertEqual(command('finish',self.base)['output'],'prototype')
  result=command('finish',dict(self.base,output='blueprint'))
  self.assertEqual(result['manufacture_limit'],1000)
  for value in (None,False,0,-1,1001,1.5,'10'):
   with self.subTest(value=value),self.assertRaises(ValueError):command('finish',dict(self.base,output='blueprint',manufacture_limit=value))
  for value in (None,True,'grant'):
   with self.assertRaises(ValueError):command('finish',dict(self.base,output=value))
 def test_unknown_and_indices(self):
  for action in ['grant','spawn','experiment','delete']:
   with self.assertRaises(ValueError):command(action,self.base)
  for value in [True,-1,4096,'1']:
   with self.assertRaises(ValueError):command('select',dict(self.base,index=value))
if __name__=='__main__':unittest.main()
