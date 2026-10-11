import re, unittest
from pathlib import Path
from server.services_protocol import command
ROOT=Path(__file__).resolve().parents[1]
class JunkDealerTests(unittest.TestCase):
 def test_sale_notice_is_not_mail(self):
  from server.mail_protocol import normalize
  notice={"message":"Junk sold for 100 credits."}
  normalize({},notice)
  self.assertEqual(notice["message"],"Junk sold for 100 credits.")
 def test_quote_validation(self):
  base={'request_id':'junk_test_123','terminal_id':'123','items':[{'item_id':'456','price':100}]}
  self.assertEqual(command('junk_sell',base)['items'],base['items'])
  for items in ([],base['items']*2,[{'item_id':'-1','price':100}],[{'item_id':'456','price':True}],[{'item_id':'456','price':-1}],['456'],[{'item_id':'456','price':2**31}]):
   with self.subTest(items=items),self.assertRaises(ValueError):command('junk_sell',dict(base,items=items))
 def test_original_dealer_categories(self):
  lua=(ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/junk_dealer/junk_dealer_conv_handler.lua').read_text()
  native=(ROOT/'server/services/SwgxrJunkDealers.h').read_text()
  bits={'generic':1,'finery':2,'arms':4,'geo':8,'tusken':16,'jedi':32,'jawa':64,'gungan':128,'corsec':256}
  handlers=dict(re.findall(r'(JunkDealer\w+ConvoHandler) = \w+:new \{\s*junkType = "(\w+)"',lua))
  self.assertEqual(len(handlers),17)
  for name,kind in handlers.items():self.assertIn('{"'+name+'",'+str(bits[kind])+'}',native)
