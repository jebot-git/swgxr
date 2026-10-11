import unittest
from server.services_protocol import command
from server.remote_gateway import POST
class Containers(unittest.TestCase):
 def test_take_requires_native_ids_and_destination(self):
  value=dict(terminal_id='10',container_id='11',item_id='12',direction='take',destination_id='13',request_id='storage_001')
  self.assertEqual(command('container_transfer',value)['destination_id'],'13')
  for field in ('terminal_id','container_id','item_id','destination_id'):
   for bad in ('0','-1','１２',str(2**64),None):
    with self.subTest(field=field,bad=bad),self.assertRaises(ValueError):command('container_transfer',dict(value,**{field:bad}))
 def test_store_and_read_are_distinct(self):
  self.assertNotIn('request_id',command('open',dict(terminal_id='10',container_id='11')))
  self.assertEqual(command('container_transfer',dict(terminal_id='10',container_id='11',item_id='12',direction='store',request_id='storage_002'))['direction'],'store')
  self.assertIn('/services/container_transfer',POST)
