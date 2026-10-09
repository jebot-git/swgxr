#!/usr/bin/env python3
"""Create a local active TRE set from separately extracted user media.

Original archives are never modified. Duplicate basenames must be byte-identical.
Run only while Core3 is stopped: its configured TRE directory is this output.
"""
from pathlib import Path
import argparse,hashlib,json,os
from archive_policy import CORE3_TRE_PRIORITY
ROOT=Path(__file__).resolve().parents[2]
def digest(path):
    h=hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda:f.read(8*1024*1024),b''):h.update(block)
    return h.hexdigest()
def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--base',type=Path,default=ROOT/'runtime/asset_sources/extracted/base/tre')
    ap.add_argument('--jtl',type=Path,default=ROOT/'runtime/asset_sources/extracted/jtl/tre')
    ap.add_argument('--tte',type=Path,default=ROOT/'runtime/asset_sources/extracted/tte/tre',help='Optional Total Experience extraction (pre-CU allowlist only)')
    ap.add_argument('--supplement',type=Path,action='append',default=[],help='Additional extraction directory; only Core3 pre-CU allowlisted names activate')
    ap.add_argument('--audit-only',action='store_true',help='Audit all sources and conflicts without changing active links')
    ap.add_argument('--output',type=Path,default=ROOT/'runtime/asset_sources/active_tre')
    args=ap.parse_args();sources=[args.base.resolve()]
    if args.jtl.exists():sources.append(args.jtl.resolve())
    if args.tte.exists():sources.append(args.tte.resolve())
    sources.extend(p.resolve() for p in args.supplement if p.resolve() not in sources)
    archives={};excluded=[]
    for source in sources:
        for path in sorted(source.rglob('*.tre')):
            if path.name not in CORE3_TRE_PRIORITY:
                excluded.append({'filename':path.name,'source':str(path),'reason':'Not in pinned Core3 pre-CU TreFiles allowlist'})
                continue
            sha=digest(path)
            if path.name in archives:
                if sha!=archives[path.name]['sha256']:raise ValueError('Conflicting duplicate TRE: '+path.name)
                archives[path.name]['identical_sources'].append(str(path))
                continue
            archives[path.name]={'filename':path.name,'source':str(path),'sha256':sha,'bytes':path.stat().st_size,'identical_sources':[]}
    if not archives:raise ValueError('No extracted TRE files available')
    missing=[n for n in CORE3_TRE_PRIORITY if n not in archives]
    if args.audit_only:
        print(json.dumps({'status':'ready','archives':len(archives),'missing':missing,'excluded':excluded,'identical_duplicate_count':sum(len(r['identical_sources']) for r in archives.values()),'mutation':False},indent=2))
        return
    args.output.mkdir(parents=True,exist_ok=True)
    # Refuse to delete or replace regular files. Only this tool's symlinks may change.
    for existing in args.output.glob('*.tre'):
        if not existing.is_symlink():raise ValueError('Output contains a non-symlink TRE: '+str(existing))
    for name,record in archives.items():
        destination=args.output/name
        if destination.is_symlink():destination.unlink()
        destination.symlink_to(os.path.relpath(record['source'],args.output))
    for stale in args.output.glob('*.tre'):
        if stale.name not in archives:stale.unlink()
    result={'expected_count':len(CORE3_TRE_PRIORITY),'missing':missing,'excluded':excluded,'priority_high_to_low':[n for n in CORE3_TRE_PRIORITY if n in archives],'archive_count':len(archives),'sources':[str(s) for s in sources],'archives':list(archives.values()),'note':'Relative links to user media extractions. No proprietary assets downloaded or original archives modified.'}
    out=args.output/'provenance.json';out.write_text(json.dumps(result,indent=2))
    print(json.dumps({'active_tre':str(args.output),'archives':len(archives),'provenance':str(out)},indent=2))
if __name__=='__main__':main()
