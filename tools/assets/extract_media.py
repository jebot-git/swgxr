#!/usr/bin/env python3
"""Extract only SWG TRE archives from user-owned local InstallShield CD images."""
from pathlib import Path
import argparse, hashlib, json, re, shutil, subprocess
ROOT=Path(__file__).resolve().parents[2]
def sha256(path):
    h=hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda:f.read(8*1024*1024),b''):h.update(block)
    return h.hexdigest()
def raw_track_to_iso(image, media):
    """Support explicit, single-track MODE1/2352 CUE images only."""
    cue=image if image.suffix.lower()=='.cue' else image.with_suffix('.cue')
    text=cue.read_text(encoding='utf-8-sig')
    files=re.findall(r'^\s*FILE\s+"([^"\n]+)"\s+BINARY\s*$',text,re.M|re.I)
    tracks=re.findall(r'^\s*TRACK\s+(\d+)\s+(\S+)\s*$',text,re.M|re.I)
    indices=re.findall(r'^\s*INDEX\s+(\d+)\s+(\S+)\s*$',text,re.M|re.I)
    if len(files)!=1 or tracks!=[('01','MODE1/2352')] or indices!=[('01','00:00:00')]:
        raise ValueError('Only one MODE1/2352 track with INDEX01 at00:00:00 is supported')
    binary=cue.parent/files[0]
    if binary.stat().st_size%2352:raise ValueError('Raw BIN size is not whole sectors')
    iso=media/(binary.stem+'.iso')
    temporary=iso.with_suffix('.iso.tmp')
    with binary.open('rb') as source,temporary.open('wb') as output:
        while block:=source.read(2352*4096):
            converted=bytearray()
            for offset in range(0,len(block),2352):
                if block[offset:offset+12]!=b'\x00'+b'\xff'*10+b'\x00' or block[offset+15]!=1:
                    raise ValueError('Unexpected raw sector header; refusing guessed conversion')
                converted.extend(block[offset+16:offset+2064])
            output.write(converted)
    temporary.replace(iso)
    return iso,[cue,binary]

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('images',nargs='*',type=Path)
    ap.add_argument('--unshield',type=Path,default=None)
    ap.add_argument('--output-root',type=Path,help='Isolated extraction root containing media/, tre/, logs/ and inventory; required for BIN/CUE')
    ap.add_argument('--bootstrap-unshield',action='store_true',help='Build pinned open-source unshield locally if not installed')
    args=ap.parse_args();images=args.images or sorted((ROOT/'runtime/asset_sources/media/base').glob('*.iso')) or sorted(ROOT.glob('LucasArts-StarWarsGalaxiesAnEmpireDivided-*.iso'))
    if not images:ap.error('No original LucasArts base ISO images found; pass another installation set explicitly')
    raw=[p for p in images if p.suffix.lower() in ('.bin','.cue')]
    if raw and (len(images)!=1 or args.output_root is None):ap.error('Pass one BIN/CUE with --output-root to isolate its InstallShield cabinets')
    seven=shutil.which('7z') or shutil.which('7zz')
    if not seven:ap.error('Install 7-Zip (7z or 7zz)')
    unshield=args.unshield or shutil.which('unshield')
    local=ROOT/'runtime/vendor/unshield'
    if not unshield and (local/'build/src/unshield').exists():unshield=local/'build/src/unshield'
    if not unshield and args.bootstrap_unshield:
        local.parent.mkdir(parents=True,exist_ok=True)
        if not local.exists():subprocess.run(['git','clone','https://github.com/twogood/unshield.git',str(local)],check=True)
        subprocess.run(['git','-C',str(local),'checkout','cbed3d19ef9cdf4e5fb86b9d65e48f1bf8d539db'],check=True)
        subprocess.run(['cmake','-S',str(local),'-B',str(local/'build'),'-DCMAKE_BUILD_TYPE=Release'],check=True)
        subprocess.run(['cmake','--build',str(local/'build'),'-j4'],check=True)
        unshield=local/'build/src/unshield'
    if not unshield:ap.error('Install unshield, pass --unshield PATH, or use --bootstrap-unshield')
    output=args.output_root.resolve() if args.output_root else ROOT/'runtime/asset_sources/extracted/base'
    media=output/'media'
    tre=output/'tre';media.mkdir(parents=True,exist_ok=True);tre.mkdir(parents=True,exist_ok=True)
    logdir=output/'logs';logdir.mkdir(parents=True,exist_ok=True)
    sources=[]
    for image in images:
        image=image.resolve()
        original_sources=[image]
        if image.suffix.lower() in ('.bin','.cue'):image,original_sources=raw_track_to_iso(image,media)
        for source in original_sources:sources.append({'filename':source.name,'bytes':source.stat().st_size,'sha256':sha256(source)})
        with (logdir/(image.stem+'-extract.log')).open('w') as log:
            subprocess.run([seven,'x','-y','-o'+str(media),str(image),'data*.cab','data*.hdr'],stdout=log,stderr=subprocess.STDOUT,check=True)
    with (logdir/'tre-extract.log').open('w') as log:
        subprocess.run([str(unshield),'-D','1','-d',str(tre),'-j','x',str(media/'data1.cab'),'*.tre'],stdout=log,stderr=subprocess.STDOUT,check=True)
    archives=[{'filename':p.name,'path':str(p.relative_to(ROOT)) if p.is_relative_to(ROOT) else str(p),'bytes':p.stat().st_size,'sha256':sha256(p)} for p in sorted(tre.rglob('*.tre'))]
    report={'media':sources,'archives':archives,'archive_count':len(archives),'provenance':'Extracted from supplied local installation media; no proprietary assets downloaded.'}
    out=output/'media_inventory.json';out.write_text(json.dumps(report,indent=2))
    print(json.dumps({'report':str(out),'archives':len(archives),'tre_dir':str(tre)},indent=2))
if __name__=='__main__':main()
