import unittest
from server.services_protocol import command
class VendorCommerceProtocol(unittest.TestCase):
 def body(self,**kw):return dict({'request_id':'commerce_test_123','terminal_id':'12','item_id':'34','price':100,'galactic_search':False},**kw)
 def test_separate_native_price_limits(self):
  self.assertEqual(command('vendor_sell',self.body(price=99999999))['price'],99999999)
  for action,price in [('vendor_sell',100000000),('bazaar_sell',20001),('vendor_sell',0),('vendor_sell',True)]:
   with self.subTest(action=action,price=price),self.assertRaises(ValueError):command(action,self.body(price=price))
 def test_listing_visibility_is_explicit_boolean(self):
  for action in ['vendor_sell','bazaar_sell']:
   self.assertFalse(command(action,self.body())['galactic_search'])
   self.assertTrue(command(action,self.body(galactic_search=True))['galactic_search'])
   for value in [0,1,'false',None]:
    with self.assertRaises(ValueError):command(action,self.body(galactic_search=value))
 def test_owned_vendor_fixed_price_not_bid(self):
  with self.assertRaises(ValueError):command('vendor_sell',self.body(auction=True))
  self.assertTrue(command('bazaar_sell',self.body(auction=True))['auction'])
 def test_recover_requires_native_vendor_and_receipt(self):
  good={'vendor_id':'123','request_id':'recover_test_001','terminal_id':'456'}
  out=command('vendor_recover',good);self.assertNotIn('terminal_id',out)
  for key in ['vendor_id','request_id']:
   bad=dict(good);bad.pop(key)
   with self.assertRaises(ValueError):command('vendor_recover',bad)
 def test_customization_does_not_accept_asset_paths_or_arbitrary_numbers(self):
  base={'vendor_id':'123','request_id':'custom_test_001','customization':{'/private/blend_nose_0':128}}
  self.assertEqual(command('vendor_customize',base)['customization'],base['customization'])
  for value in [None,[],{'../evil':1},{'a':True},{'a':256},{'a':-1},{'a':1.5},{'a':float('nan')},{str(i):1 for i in range(129)}]:
   with self.subTest(value=value),self.assertRaises(ValueError):command('vendor_customize',dict(base,customization=value))
 def test_vendor_buy_price_and_required_ids(self):
  self.assertEqual(command('vendor_buy',{'terminal_id':'12','listing_id':'34','request_id':'vendorbuy001','price':90000})['price'],90000)
  for action in ['vendor_buy','vendor_retrieve','vendor_cancel']:
   with self.assertRaises(ValueError):command(action,{'terminal_id':'12','request_id':'vendorbuy001','price':100})
if __name__=='__main__':unittest.main()
