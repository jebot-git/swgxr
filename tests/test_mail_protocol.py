import unittest
from unittest.mock import patch
from server.mail_protocol import fields,normalize,plain
from server.services_protocol import command
class MailProtocolTests(unittest.TestCase):
 def test_space_mail_has_no_ground_movement(self):
  value=command('mail_send',dict(zone='space_tatooine',position=[float('nan'),0,0],building_id='POB',recipient='Tester',subject='Hello',body='Text',request_id='mailtest-123'))
  self.assertNotIn('position',value);self.assertEqual(value['recipient'],'tester')
 def test_invalid_fields(self):
  for change in ({'recipient':''},{'subject':''},{'body':'x'*4001},{'recipient':'one two'},{'body':'\0'}):
   with self.assertRaises(ValueError):fields('mail_send',dict(dict(recipient='Tester',subject='Hello',body='Body'),**change))
  for value in ['0',str(2**64),'-1','1.0',1]:
   with self.assertRaises(ValueError):fields('mail_read',dict(mail_id=value))
 def test_wire_requires_reviewed_identity(self):
  data=dict(recipient='Tester',recipient_id='42',amount=100,fee=5)
  self.assertEqual(fields('bank_pay',data),dict(data,recipient='tester'))
  for field,value in [('amount',True),('amount',0),('fee',-1),('recipient_id','0')]:
   with self.assertRaises(ValueError):fields('bank_pay',dict(data,**{field:value}))
 def test_original_report_parameters(self):
  state={'mail':{'messages':[{'subject':'@survey:title'}]}};mutation={'message':{'subject':'@survey:title','body':'','parameters':[{'file':'survey','stringID':'report','TT':{'customName':'Naboo'},'DI':23}]}}
  def display(file,key,fallback):return {'title':'Survey report','report':'%TT: %DI resources'}.get(key,fallback)
  with patch('server.mail_protocol.display',display):normalize(state,mutation)
  self.assertEqual(mutation['message']['body'],'Naboo: 23 resources');self.assertEqual(state['mail']['messages'][0]['subject'],'Survey report')
  self.assertEqual(plain('\\#ff8800Ore\\#.'),'Ore')
