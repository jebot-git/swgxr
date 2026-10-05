#!/usr/bin/env python3
"""Exercise real Core3 customization persistence through distinct logins."""
import argparse,json,secrets,string,urllib.request,urllib.error
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def call(path,data=None):
    req=urllib.request.Request('http://127.0.0.1:18080'+path,data=json.dumps(data).encode() if data is not None else None,headers={'Content-Type':'application/json'})
    try:
        with urllib.request.urlopen(req,timeout=150) as stream:return json.load(stream)
    except urllib.error.HTTPError as exc:raise RuntimeError(exc.read().decode()) from exc
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--account');ap.add_argument('--expect-id');ap.add_argument('--report',default='appearance-roundtrip.json');args=ap.parse_args()
    account=args.account or 'appearance'+''.join(secrets.choice(string.ascii_lowercase) for _ in range(6))
    options=call('/creation-options');assert len(options['races'])==20 and len(options['professions'])==6
    race=options['races']['twilek_female'];hair=race['hair'][0]
    request={'account':account,'name':'Nera'+''.join(secrets.choice('aeioulnrt') for _ in range(5)),
        'species':'twilek','sex':'female','profession':'science_medic','height':1.03,
        'customization':{'/shared_owner/blend_skinny':87,'/shared_owner/blend_flat_chest':-1,'/shared_owner/index_color_skin':25},
        'hair_template':hair['template'],'hair_customization':{'/shared_owner/index_color_pattern':31},
        'biography':'A medic learning the paths through Mos Eisley.'}
    created=call('/characters',request)['character'] if not args.expect_id else None
    oid=args.expect_id or created['id'];listed=call('/characters?account='+account)
    assert any(c['id']==oid and c['race']=='twilek_female' for c in listed['characters'])
    readback=call('/characters/'+oid+'?account='+account)['character'];entered=call('/enter',{'account':account,'character_id':oid})
    c=entered['character'];a=c['appearance']
    assert c['race']=='twilek_female' and c['profession']=='science_medic'
    assert 'science_medic_novice' in c['skills'] and c['biography']==request['biography']
    assert abs(a['height']-request['height'])<1e-5 and a['customization']==request['customization'],a
    assert a['hair']['template']==request['hair_template'].replace('/hair_twilek','/shared_hair_twilek')
    assert a['hair']['customization']==request['hair_customization'],a['hair']
    assert len([e for e in a['equipment'] if '/wearables/' in e['template']])>=2
    assert a==readback['appearance'] and (created is None or a==created['appearance'])
    report={'success':True,'account':account,'request':request,'created':created,'readback':readback,'entered':entered}
    path=ROOT/'runtime/server'/args.report;path.write_text(json.dumps(report,indent=2));print(json.dumps({'success':True,'account':account,'id':oid,'report':str(path)}))
if __name__=='__main__':main()
