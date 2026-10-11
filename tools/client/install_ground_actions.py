#!/usr/bin/env python3
"""Apply an extracted private animation delta to matching user-prepared assets.

Use --check before installation. Never replaces body geometry or skeletons.
"""
import argparse,hashlib,json,shutil
from pathlib import Path

def safe(root,relative):
 p=(root/relative).resolve()
 if not p.is_relative_to(root.resolve()):raise ValueError('Path escapes package root')
 return p
def install(root,source,check=False):
 manifest=json.loads((source/'sha256.json').read_text())
 for rel,digest in manifest.items():
  with safe(source,rel).open('rb') as f:
   if hashlib.file_digest(f,'sha256').hexdigest()!=digest:raise ValueError('Asset hash mismatch: '+rel)
 updates=json.loads((source/'animation-updates.json').read_text());ready=[];missing=[]
 for update in updates:
  target=safe(root,update['model'])
  if not target.exists():missing.append(update['model']);continue
  body=json.loads(target.read_text());digest=hashlib.sha256(json.dumps(body['bones'],sort_keys=True,separators=(',',':')).encode()).hexdigest()
  if digest!=update['bones_sha256']:raise ValueError('Skeleton mismatch: '+update['model'])
  ready.append((target,body,update['animation_library']))
 if not ready:raise ValueError('No matching prepared NPC models')
 if not check:
  for rel in manifest:
   if not rel.startswith('runtime/assets/'):continue
   target=safe(root,rel);target.parent.mkdir(parents=True,exist_ok=True);temp=target.with_suffix(target.suffix+'.ground-new');shutil.copy2(safe(source,rel),temp);temp.replace(target)
  for target,body,entries in ready:
   body.setdefault('animation_library',{}).update(entries);temp=target.with_suffix('.ground-new');temp.write_text(json.dumps(body,separators=(',',':')));temp.replace(target)
 return {'checked_only':check,'models':len(ready),'absent_models':len(missing)}
def main():
 p=argparse.ArgumentParser();p.add_argument('--root',type=Path,required=True);p.add_argument('--source',type=Path,required=True);p.add_argument('--check',action='store_true');a=p.parse_args();print(json.dumps(install(a.root.resolve(),a.source.resolve(),a.check)))
if __name__=='__main__':main()
