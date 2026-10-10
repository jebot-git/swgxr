#!/usr/bin/env python3
"""Refresh source frame messages in existing converted skeletal clips."""
import hashlib,json
from pathlib import Path
from swg_formats import TreSet
from character_animations import animation_messages
ROOT=Path(__file__).resolve().parents[2]

def main():
    tree=TreSet(ROOT/'runtime/asset_sources/active_tre');cache={};updated=0;failures=[]
    candidates=[]
    for path in (ROOT/'runtime/assets').rglob('*.json'):
        if any(part in ('models','animations','bodies') for part in path.parts):candidates.append(path)
    for path in candidates:
        raw=path.read_bytes()
        if b'"animations"' not in raw and not (b'"tracks"' in raw and b'.ans"' in raw):continue
        value=json.loads(raw);clips=list(value.get('animations',{}).values())
        if 'tracks' in value and str(value.get('source','')).endswith('.ans'):clips.append(value)
        changed=False
        for clip in clips:
            if not isinstance(clip,dict) or not str(clip.get('source','')).endswith('.ans'):continue
            source=clip['source']
            try:
                if source not in cache:cache[source]=animation_messages(tree.read(source))
                if clip.get('messages')!=cache[source]:clip['messages']=cache[source];changed=True
            except Exception as error:failures.append(dict(source=source,error=str(error)))
        if changed:path.write_text(json.dumps(value,separators=(',',':'))+'\n');updated+=1
    report=dict(updated_files=updated,source_clips=len(cache),failures=failures)
    (ROOT/'runtime/assets/animation_audio_report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
    if failures:raise SystemExit(1)
if __name__=='__main__':main()
