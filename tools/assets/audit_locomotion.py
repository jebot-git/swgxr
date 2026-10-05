#!/usr/bin/env python3
"""Audit source ANS cadence and reconstructed source-rig foot heights.

No media writes or replacements. Source LOCT is measured, not a gameplay speed.
"""
import argparse, hashlib, json, math, struct
from pathlib import Path
from swg_formats import TreSet, parse_iff, cstring


def sample(keys, time, rotation=False):
    if len(keys)==1 or time<=keys[0][0]: return keys[0][1:]
    if time>=keys[-1][0]: return keys[-1][1:]
    for a,b in zip(keys,keys[1:]):
        if a[0]<=time<=b[0]:
            w=(time-a[0])/(b[0]-a[0]); a=a[1:]; b=b[1:]
            if rotation and sum(x*y for x,y in zip(a,b))<0:b=[-v for v in b]
            r=[x*(1-w)+y*w for x,y in zip(a,b)]
            if rotation:
                norm=math.sqrt(sum(v*v for v in r));r=[v/norm for v in r]
            return r


def mul(a,b):
    x,y,z,w=a;X,Y,Z,W=b
    return [w*X+x*W+y*Z-z*Y,w*Y-x*Z+y*W+z*X,w*Z+x*Y-y*X+z*W,w*W-x*X-y*Y-z*Z]


def rotate(q,v): return mul(mul(q,[*v,0]),[-q[0],-q[1],-q[2],q[3]])[:3]


def positions(bones, tracks, time, root_positions=True):
    poses=[];by_name={t['name']:t for t in tracks}
    for bone in bones:
        track=by_name.get(bone['name']);q=sample(track['rotations'],time,True) if track else bone['rest_rotation']
        p=sample(track['positions'],time) if track and (root_positions or bone['name']!='root') else bone['rest_position']
        if bone['parent']>=0:
            pq,pp=poses[bone['parent']];p=[x+y for x,y in zip(rotate(pq,p),pp)];q=mul(pq,q)
        poses.append((q,p))
    return {bone['name']:poses[i][1] for i,bone in enumerate(bones)}


def main():
    ap=argparse.ArgumentParser();ap.add_argument('--tre-dir',type=Path,default=Path('runtime/assets/active_tre'));ap.add_argument('--characters',type=Path,default=Path('runtime/assets/characters'));ap.add_argument('--output',type=Path,default=Path('runtime/evidence/locomotion-source-audit.json'));args=ap.parse_args()
    tre=TreSet(args.tre_dir);catalog=json.loads((args.characters/'catalog.json').read_text());report={'source':'original ANS LOCT/MSGS + exported source skeleton/pose tracks','coordinate_system':'Godot Y-up -Z forward','races':{},'clips':{},'notes':['LOCT float is source average speed, validated against endpoint displacement divided by duration.','Height samples use source absolute local poses at 30Hz, quaternion normalized interpolation.','No terrain, IK, avatar height customization or headset transforms included.','The exported crouch clip is authored kneeling, not a generic symmetric physical squat.']}
    for race,definition in catalog['races'].items():
        model=json.loads((args.characters/definition['body']).read_text());summary={}
        for state,clip in model['animations'].items():
            if state not in ('idle','walk','run','strafe_left','strafe_right','backpedal','crouch','crouch_walk','jump'):continue
            path=clip['source']
            if path not in report['clips']:
                raw=tre.read(path);root=parse_iff(raw);compressed=root.tag=='CKAT';frame_fmt='h' if compressed else 'i';count_fmt='H' if compressed else 'I';record_fmt='<'+frame_fmt+'3f';header_fmt='<f'+count_fmt
                row={'source':path,'sha256':hashlib.sha256(raw).hexdigest(),'duration':clip['length'],'fps':clip['fps'],'source_speed_scale':clip.get('source_speed_scale',1),'loop':clip['loop']}
                loc=next(root.walk('LOCT'),None)
                if loc:
                    speed,count=struct.unpack_from(header_fmt,loc.data);size=struct.calcsize(record_fmt);offset=struct.calcsize(header_fmt);assert len(loc.data)==offset+size*count
                    keys=[struct.unpack_from(record_fmt,loc.data,offset+i*size) for i in range(count)]
                    delta=[keys[-1][j]-keys[0][j] for j in range(1,4)];delta[2]*=-1
                    row.update({'source_average_speed':speed,'source_cycle_displacement':delta,'measured_average_speed':math.sqrt(sum(x*x for x in delta))/clip['length']})
                messages=[]
                for chunk in root.walk('MESG'):
                    count=struct.unpack_from('<'+count_fmt,chunk.data)[0];offset=struct.calcsize('<'+count_fmt);name,offset=cstring(chunk.data,offset);frames=struct.unpack_from('<'+frame_fmt*count,chunk.data,offset)
                    messages.append({'name':name,'frames':frames,'seconds':[f/clip['fps'] for f in frames]})
                row['messages']=messages;report['clips'][path]=row
            samples=[positions(model['bones'],clip['tracks'],i/30) for i in range(round(clip['length']*30)+1)]
            foot_names=['lankle','rankle','ltoe','rtoe','head','root']
            summary[state]={'source':path,'height_ranges':{name:[min(s[name][1] for s in samples),max(s[name][1] for s in samples)] for name in foot_names}}
        report['races'][race]=summary
    args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({'races':len(report['races']),'source_clips':len(report['clips']),'output':str(args.output)}))

if __name__=='__main__':main()
