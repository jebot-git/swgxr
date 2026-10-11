"""Bounded mail, native bank wire and survey-probe presentation fields."""
import re
try:
 from .planets import planet
 from .datapad_protocol import display
except ImportError:
 from planets import planet
 from datapad_protocol import display
ACTIONS=('mail_status','mail_list','mail_read','mail_send','mail_delete','mail_waypoint','bank_quote','bank_pay','probe_status','probe_launch')
READS={'mail_status','mail_list','bank_quote','probe_status'}
def fields(action,data):
 out={}
 for key in {'mail_read':('mail_id',),'mail_delete':('mail_id',),'mail_waypoint':('mail_id',),'bank_pay':('recipient_id',),'probe_launch':('probe_id','tool_id')}.get(action,()):
  value=data.get(key)
  if not isinstance(value,str) or not re.fullmatch(r'[0-9]{1,20}',value) or not 0<int(value)<2**64:raise ValueError('Valid native '+key+' required.')
  out[key]=value
 if action in ('mail_send','bank_quote','bank_pay'):
  name=data.get('recipient','')
  if not isinstance(name,str) or not re.fullmatch(r"[A-Za-z][A-Za-z'\-]{1,39}",name.strip()):raise ValueError('Enter the recipient’s first character name.')
  out['recipient']=name.strip().lower()
 if action=='mail_send':
  for key,limit in [('subject',128),('body',4000)]:
   value=data.get(key)
   if not isinstance(value,str) or not value.strip() or len(value)>limit or any(ord(c)<32 and c not in '\n\t' for c in value):raise ValueError('Mail '+key+' is empty or too long.')
   out[key]=value.strip()
 if action in ('bank_quote','bank_pay'):
  amount=data.get('amount')
  if type(amount) is not int or not 0<amount<=2000000000:raise ValueError('Positive integer credit amount required.')
  out['amount']=amount
  if action=='bank_pay':
   fee=data.get('fee')
   if type(fee) is not int or not 0<=fee<=100000000:raise ValueError('Reviewed bank fee required.')
   out['fee']=fee
 if action=='mail_waypoint':
  index=data.get('index')
  if type(index) is not int or not 0<=index<64:raise ValueError('Valid mail waypoint required.')
  out['index']=index
 if action=='probe_launch':out['target_planet']=planet(data.get('target_planet'))
 return out

def plain(value):
 # Original SWG report color markers are not Godot BBCode.
 return re.sub(r'\\#(?:[0-9a-fA-F]{6}|p[a-zA-Z0-9_]+|\.)','',str(value))
def translated(value):
 value=plain(value)
 if re.fullmatch(r'@?[A-Za-z0-9_/]+:[A-Za-z0-9_]+',value):
  table,key=value.lstrip('@').split(':',1);return display(table,key,value)
 return value

def parameter(value):
 if not isinstance(value,dict):return plain(value)
 if value.get('customName'):return translated(value['customName'])
 sid=value.get('stringID',{})
 if isinstance(sid,dict):return display(sid.get('file',''),sid.get('stringID',''),'')
 return translated(sid) if sid else ''

def normalize(state,mutation):
 mail=state.get('mail')
 if mail:
  for row in mail.get('messages',[]):row['subject']=translated(row.get('subject',''))
 message=mutation.get('message')
 if isinstance(message,dict):
  message['subject']=translated(message.get('subject',''));parts=[translated(message.get('body',''))]
  for row in message.pop('parameters',[]):
   body=display(row.get('file',''),row.get('stringID',''),'')
   for key in ('TT','TU','TO'):body=body.replace('%'+key,parameter(row.get(key,{})))
   body=body.replace('%DI',str(row.get('DI',0))).replace('%DF',str(row.get('DF',0)))
   parts.append(body)
  message['body']='\n'.join(p for p in parts if p)
 for kind in ('probes','tools'):
  for row in state.get('survey_probes',{}).get(kind,[]):row['name']=translated(row.get('name',''))
