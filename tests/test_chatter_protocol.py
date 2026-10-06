import unittest
from unittest.mock import patch
from server import chatter_protocol as speech
class ChatterProtocolTests(unittest.TestCase):
 def setUp(self):
  self.language=dict(id=2,key='rodese',name='Rodese',audible=True,syllables={'a':'ee','b':'yu','i':'ts'})
  self.row=dict(id='123',actor_id='456',name='Test speaker',position=[1,2,3],zone='tatooine',building_id='0',cell_index=0,language_id=2,language_key='rodese',message={'text':'Ab, i!'},comprehension_before=0,comprehension_after=2.5,age_ms=10)
 def normalize(self,rows):
  with patch.object(speech,'catalog',return_value={2:self.language}):return speech.normalize(dict(sequence=1,events=rows,languages=[]))
 def test_unknown_language_uses_original_case_and_punctuation_mapping(self):
  row=self.normalize([self.row])['events'][0];self.assertEqual(row['text'],'EEyu, ts!');self.assertFalse(row['understood']);self.assertNotIn('message',row)
 def test_comprehension_completion_keeps_clear_text_without_raw_payload(self):
  row=self.normalize([dict(self.row,comprehension_after=100)])['events'][0];self.assertEqual(row['text'],'Ab, i!');self.assertTrue(row['understood'])
 def test_repeated_snapshot_never_changes_progress_or_rescrambles(self):
  first=self.normalize([self.row]);second=self.normalize(first['events']);self.assertEqual(first,second);self.assertEqual(second['events'][0]['comprehension_after'],2.5)
 def test_invalid_expired_duplicate_and_unbounded_event_inputs_are_filtered(self):
  out=self.normalize([self.row,self.row,dict(self.row,id='１２４'),dict(self.row,id='125',age_ms=6000),dict(self.row,id='126',position=[float('nan'),2,3])]);self.assertEqual(len(out['events']),1)
 def test_source_parameter_localization(self):
  with patch.object(speech,'display',side_effect=lambda table,key,fallback: {'greeting':'Hello %TT, %DI times.','target':'visitor'}.get(key,fallback)):
   text=speech.message_text({'file':'original','stringID':'greeting','TT':{'stringID':{'file':'original','stringID':'target'}},'DI':2},{})
  self.assertEqual(text,'Hello visitor, 2 times.')
 def test_inaudible_unknown_never_exposes_plaintext(self):
  self.language['audible']=False;self.language['syllables']={}
  result=self.normalize([self.row])['events'][0];self.assertEqual(result['text'],'[Unfamiliar body language]');self.assertNotIn('Ab',result['text'])
 def test_no_catalog_means_no_untranslated_text_leak(self):
  with patch.object(speech,'catalog',return_value={}):self.assertEqual(speech.normalize(dict(events=[self.row]))['events'],[])
if __name__=='__main__':unittest.main()
