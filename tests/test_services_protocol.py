import unittest
from unittest.mock import patch
from server.services_protocol import command,snapshot
class ServicesProtocolTests(unittest.TestCase):
 def data(self,**kw):return dict(request_id='services_test_001',position=[3527,5,-4820],terminal_id='123',**kw)
 def test_strict_amounts(self):
  for value in (True,0,-1,1.5,2000000001,'12'):
   with self.assertRaises(ValueError):command('bank_transfer',self.data(amount=value,direction='deposit'))
  self.assertEqual(command('bank_transfer',self.data(amount=100,direction='deposit'))['amount'],100)
 def test_ids_and_cells(self):
  for field in ('terminal_id','target_id','listing_id','mission_id','ticket_id'):
   action={'terminal_id':'open','target_id':'pay','listing_id':'bazaar_buy','mission_id':'mission_accept','ticket_id':'travel_board'}[field]
   d=self.data(amount=1,price=1);d[field]='-1'
   with self.assertRaises(ValueError):command(action,d)
  for pair in [('0',1),('12',0),('12',True),('12',257)]:
   with self.assertRaises(ValueError):command('status',self.data(building_id=pair[0],cell_index=pair[1]))
 def test_positions(self):
  for p in ([0,float('nan'),0],[0,9000,0],[True,0,0],[0,0]):
   with self.assertRaises(ValueError):command('status',{'position':p})
 def test_bound_quotes_and_destinations(self):
  self.assertEqual(command('travel_purchase',self.data(destination_id='Mos Espa'))['destination_id'],'Mos Espa')
  for value in ('Mos Espa;echo','',None,'a'*101):
   with self.assertRaises(ValueError):command('travel_purchase',self.data(destination_id=value))
  with self.assertRaises(ValueError):command('bazaar_buy',self.data(price=20001))
  with self.assertRaises(ValueError):command('bazaar_buy',self.data(price=200,max_price=199))
 def test_snapshot_shape_and_native_transport(self):
  raw={'source_kind':'core3_services','character_id':'100','player':{},'wallet':{'cash':12,'bank':30},'terminals':[],'tickets':[],'terminal':{},'shuttle':{'id':'5','landed':False},'mutation':{'success':True,'request_id':'trip_001','transport_destination':{'position':[1,2,3],'zone':'tatooine'}}}
  value=snapshot(raw,'100');self.assertEqual(value['state']['shuttles'],[raw['shuttle']]);self.assertEqual(value['transport']['destination'],raw['mutation']['transport_destination']);self.assertTrue(value['ok'])
  with self.assertRaises(ValueError):snapshot(raw,'101')
 def test_all_mutations_idempotency_key(self):
  for a in ('bank_transfer','pay','mission_accept','travel_board','bazaar_retrieve'):
   with self.assertRaises(ValueError):command(a,{'request_id':'bad'})
 def test_mission_target_uses_original_string_table(self):
  raw={'source_kind':'core3_services','character_id':'100','terminal':{'id':'2','kind':'mission','terminal_type':'scout','missions':[{'id':'3','target':'@item_n:recon_target'}]},'missions':[]}
  with patch('server.services_protocol.display',return_value='Reconnaissance location'):
   state=snapshot(raw,'100')['state']
  self.assertEqual(state['terminal']['missions'][0]['target'],'Reconnaissance location')
  self.assertEqual(state['terminal']['terminal_type'],'scout')
if __name__=='__main__':unittest.main()
