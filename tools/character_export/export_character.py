#!/usr/bin/env python3
"""Export your Core3 character and current equipment to a self-contained VRM 1.0."""
from __future__ import annotations
import argparse
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode, urlsplit
from urllib.request import Request, build_opener, HTTPRedirectHandler

from vrm import ExportError, make_vrm
ROOT=Path(__file__).resolve().parents[2]
MAX_JSON=32*1024*1024

class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self,*args,**kwargs):
        raise ExportError('The character endpoint redirected. Use its final trusted URL.')

def read_json(path:Path)->dict:
    if path.stat().st_size>MAX_JSON:raise ExportError('Snapshot exceeds 32 MiB.')
    try:value=json.loads(path.read_text())
    except (ValueError,UnicodeError) as error:raise ExportError('Snapshot is not valid JSON.') from error
    if not isinstance(value,dict):raise ExportError('Expected a character JSON object.')
    return value

def normalize_snapshot(envelope:dict, character_id:str|None=None)->dict:
    character=envelope.get('character')
    if not isinstance(character,dict):raise ExportError('Expected a full character response with a character object.')
    appearance=character.get('appearance')
    if not isinstance(appearance,dict) or not appearance.get('race',character.get('race')):
        raise ExportError('Character has no appearance or race.')
    if character_id and str(character.get('id',''))!=character_id:raise ExportError('Server returned a different character.')
    equipment=character.get('equipment',appearance.get('equipment'))
    if not isinstance(equipment,list):raise ExportError('Current equipment array is required; default outfits are not exported.')
    if not all(isinstance(item,dict) and isinstance(item.get('template'),str) for item in equipment):
        raise ExportError('Malformed equipment records.')
    # Do not carry account tokens, unrelated session state or other response data
    # into the temporary export snapshot or the resulting VRM.
    fields=['id','name','race','species','sex','profession','professions']
    clean={key:character[key] for key in fields if key in character}
    clean['appearance']={key:appearance[key] for key in ['race','height','customization','hair','source'] if key in appearance}
    item_fields=['id','name','template','shared_template','customization','equipped_slots','containment_type']
    clean['equipment']=[{key:item[key] for key in item_fields if key in item} for item in equipment]
    hair=clean['appearance'].get('hair')
    if isinstance(hair,dict):clean['appearance']['hair']={key:hair[key] for key in item_fields if key in hair}
    return {'character':clean}

def connection(base:str,account:str|None,token:str|None)->tuple[str,dict]:
    parsed=urlsplit(base)
    if parsed.scheme not in ('http','https') or not parsed.hostname or parsed.username or parsed.password or parsed.query or parsed.fragment:
        raise ExportError('Use a plain HTTP(S) endpoint URL without credentials, query or fragment.')
    try:loopback=ipaddress.ip_address(parsed.hostname).is_loopback
    except ValueError:loopback=parsed.hostname.lower()=='localhost'
    if not loopback and parsed.scheme!='https':raise ExportError('Remote character export requires HTTPS.')
    if not loopback and not token:raise ExportError('Remote character export requires an existing access token.')
    if token:
        if '\n' in token or '\r' in token:raise ExportError('Malformed access token.')
        return base.rstrip('/'),{'Authorization':'Bearer '+token}
    if not account:raise ExportError('Local export requires --account. Remote export uses --token-file or SWGXR_EXPORT_TOKEN.')
    return base.rstrip('/'),{}

def request_json(base:str,path:str,account:str|None,token:str|None)->dict:
    base,headers=connection(base,account,token)
    query='?'+urlencode({'account':account}) if not token else ''
    try:
        with build_opener(NoRedirect()).open(Request(base+path+query,headers=headers),timeout=90) as response:
            data=response.read(MAX_JSON+1)
        if len(data)>MAX_JSON:raise ExportError('Character response exceeds 32 MiB.')
        value=json.loads(data)
    except HTTPError as error:
        advice={401:'The access token expired or is invalid.',403:'The account does not own this character.',
                409:'The account has a conflicting active session. Select its active character or try after logging out.',
                503:'Core3 is busy or not ready. Try again shortly.'}.get(error.code,'Character endpoint request failed.')
        raise ExportError(f'HTTP {error.code}: {advice}') from None
    except (URLError,TimeoutError) as error:raise ExportError('Cannot reach the character endpoint: '+str(error.reason if isinstance(error,URLError) else error)) from None
    except ValueError:raise ExportError('Character endpoint returned invalid JSON.') from None
    if not isinstance(value,dict) or value.get('backend')!='core3':raise ExportError('Endpoint did not return a Core3 response.')
    return value

def choose_character(args,token):
    if args.character and not args.list:
        if not args.character.isdecimal():raise ExportError('--character must be a decimal character ID.')
        return args.character
    roster=request_json(args.url,'/characters',args.account,token).get('characters',[])
    if not roster:raise ExportError('No characters returned for this account.')
    for i,entry in enumerate(roster,1):print(f"{i}. {entry['name']} ({entry['id']}, {entry.get('race','')})")
    if args.list:return None
    if not sys.stdin.isatty():raise ExportError('Choose a character using --character ID.')
    try:choice=int(input('Character number: '))-1
    except ValueError:raise ExportError('Enter a listed character number.') from None
    if not 0<=choice<len(roster):raise ExportError('Character number is out of range.')
    return str(roster[choice]['id'])

def publish(output:Path,data:bytes,metadata:dict,force:bool=False)->None:
    """Publish both files without following or clobbering a raced report path."""
    report=output.with_suffix('.vrm.json')
    staged=[];published=[]
    try:
        for target,payload in [(output,data),(report,(json.dumps(metadata,indent=2)+'\n').encode())]:
            descriptor,path=tempfile.mkstemp(prefix='.'+target.name+'.',dir=target.parent)
            temp=Path(path);staged.append((temp,target))
            with os.fdopen(descriptor,'wb') as stream:stream.write(payload)
        for temp,target in staged:
            if force:os.replace(temp,target)
            else:
                os.link(temp,target)
                published.append((temp,target))
    except OSError:
        # Roll back only our own newly linked inode, never another writer's file.
        if not force:
            for temp,target in published:
                try:
                    if os.path.samestat(temp.stat(),target.lstat()):target.unlink()
                except FileNotFoundError:pass
        raise
    finally:
        for temp,_target in staged:temp.unlink(missing_ok=True)

def export(snapshot:dict,output:Path,godot:str,author:str='',force:bool=False)->dict:
    output=output.expanduser().resolve()
    if output.suffix.lower()!='.vrm':raise ExportError('Output filename must end in .vrm.')
    try:relative=output.relative_to(ROOT)
    except ValueError:relative=None
    if relative and relative.parts[0]!='runtime':raise ExportError('Within this repository, generated avatars must be saved under ignored runtime/.')
    report_path=output.with_suffix('.vrm.json')
    if not force and (output.exists() or report_path.exists()):raise ExportError('Output already exists; choose a new filename or use --force.')
    binary=shutil.which(godot)
    if not binary:raise ExportError('Godot not found; pass --godot /path/to/godot.')
    if not (ROOT/'runtime/assets/characters/catalog.json').is_file():raise ExportError('Local SWG character assets are not prepared. Run the project asset setup first.')
    output.parent.mkdir(parents=True,exist_ok=True)
    work_root=ROOT/'runtime/character_exports';work_root.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.export-',dir=work_root) as work:
        work=Path(work);source=work/'character.json';glb=work/'character.glb';detail=work/'report.json'
        source.write_text(json.dumps(snapshot));source.chmod(0o600)
        print('Reconstructing character, baking materials and exporting the rig…',flush=True)
        command=[binary,'--log-file',str(work/'godot.log'),'--headless','--xr-mode','off','--path',str(ROOT/'client'),'--script','res://tools/character_export.gd',
                 '--','--snapshot',str(source),'--output',str(glb),'--report',str(detail)]
        child_env=os.environ.copy();child_env.pop('SWGXR_EXPORT_TOKEN',None)
        try:result=subprocess.run(command,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=600,env=child_env)
        except subprocess.TimeoutExpired:raise ExportError('Godot export exceeded 10 minutes; no avatar was written.') from None
        if result.returncode or not glb.is_file():
            error='; '.join(map(str,read_json(detail).get('errors',[]))) if detail.is_file() else ''
            raise ExportError('Godot could not export the character. '+str(error)+'\n'+result.stdout[-5000:])
        conversion=read_json(detail)
        if not conversion.get('ok') or conversion.get('errors'):raise ExportError('Converter did not confirm a complete export.')
        data,validation=make_vrm(glb.read_bytes(),str(snapshot['character'].get('name') or 'SWG character'),author,{bone['name']:int(bone['gltf_node']) for bone in conversion.get('bones',[])},str(conversion.get('forward','')).split(' ')[0])
        metadata={'format':'VRM 1.0','character_id':str(snapshot['character'].get('id','')),
                  'source':'offline snapshot' if snapshot.get('offline') else 'Core3 character snapshot',
                  'snapshot_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
                  'source_catalog_sha256':{str(path.relative_to(ROOT)):hashlib.sha256(path.read_bytes()).hexdigest() for path in [ROOT/'runtime/assets/characters/catalog.json',ROOT/'runtime/assets/inventory/catalog.json'] if path.is_file()},
                  'vrm_sha256':hashlib.sha256(data).hexdigest(),'validation':validation,'conversion':conversion,
                  'limitations':['No facial expression presets, automatic blink/lip sync or spring-bone simulation.'],
                  'validation_scope':'Structural checks and Godot export; target avatar application compatibility must be checked separately.'}
        publish(output,data,metadata,force)
    print(f'Exported: {output}\nReport: {report_path}')
    return metadata

def main(argv=None)->int:
    parser=argparse.ArgumentParser(description=__doc__,formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    parser.add_argument('--snapshot',type=Path,help='Offline full character response JSON; no network calls')
    parser.add_argument('--url',default='http://127.0.0.1:18080',help='Local adapter or authenticated HTTPS gateway')
    parser.add_argument('--account',help='Local adapter account (not used with a token)')
    parser.add_argument('--token-file',type=Path,help='Existing gateway token file; alternatively set SWGXR_EXPORT_TOKEN')
    parser.add_argument('--character',help='Character ID; omit for interactive choice')
    parser.add_argument('--list',action='store_true',help='List account characters and exit')
    parser.add_argument('--output',type=Path,help='Output .vrm; defaults under runtime/character_exports')
    parser.add_argument('--author',default='',help='Optional avatar assembler credit; original asset credit is retained')
    parser.add_argument('--godot',default='godot',help='Godot executable')
    parser.add_argument('--force',action='store_true',help='Replace an existing output and report')
    args=parser.parse_args(argv)
    try:
        if args.snapshot:
            if args.list:raise ExportError('--snapshot and --list cannot be combined.')
            snapshot=normalize_snapshot(read_json(args.snapshot));snapshot['offline']=True
        else:
            token=args.token_file.read_text().strip() if args.token_file else os.environ.get('SWGXR_EXPORT_TOKEN')
            character=choose_character(args,token)
            if character is None:return 0
            envelope=request_json(args.url,'/characters/'+character,args.account,token)
            if envelope.get('character',{}).get('appearance',{}).get('source')!='core3_replication':raise ExportError('Server appearance is not native Core3 replication.')
            snapshot=normalize_snapshot(envelope,character)
        name=re.sub(r'[^A-Za-z0-9_-]+','-',str(snapshot['character'].get('name','character'))).strip('-') or 'character'
        identity=re.sub(r'[^A-Za-z0-9_-]+','-',str(snapshot['character'].get('id','offline')))
        output=args.output or ROOT/'runtime/character_exports'/f"{name}-{identity}.vrm"
        export(snapshot,output,args.godot,args.author,args.force)
        return 0
    except (ExportError,OSError,ValueError) as error:print('Export failed: '+str(error),file=sys.stderr);return 1
    except KeyboardInterrupt:print('Export cancelled.',file=sys.stderr);return 130

if __name__=='__main__':raise SystemExit(main())
