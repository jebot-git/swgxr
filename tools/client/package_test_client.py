#!/usr/bin/env python3
"""Assemble a code-only portable test client with separate verified data import."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import ssl
import subprocess
import tarfile
import zipfile
try:
    from . import windows_python
except ImportError:
    import windows_python

ROOT=Path(__file__).resolve().parents[2]
TARGETS=('linux-x86_64','windows-x86_64')


def sha(path):
    with Path(path).open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()


def included(relative,target):
    parts=relative.parts
    if any(p in ('.git','__pycache__','shader_cache') for p in parts):return False
    if parts[0] in ('tests','benchmarks'):return False
    if parts[0]=='tools' and relative.name not in {name+suffix for name in ('portable_character_export','character_exporter','avatar_export_materials') for suffix in ('.gd','.gd.uid')}:return False
    if parts[:3]==('addons','godot-xr-tools','examples'):return False
    # Unreferenced upstream editor demonstration scenes run preview code while
    # exporting; the used keyboard2D/viewport and tracked hand resources remain.
    if relative.as_posix() in ('addons/godot-xr-tools/objects/grab_points/grab_point_hand_left.tscn','addons/godot-xr-tools/objects/grab_points/grab_point_hand_right.tscn','addons/godot-xr-tools/objects/virtual_keyboard.tscn'):return False
    if parts[:2]==('native','src'):return target=='windows-x86_64'
    if target=='linux-x86_64' and parts[0]=='native' and relative.name in ('SConstruct','build_profile.json'):return False
    if parts[:3]==('native','bin','build'):return False
    if parts[0]=='.godot':return len(parts)>1 and parts[1] in ('imported','global_script_class_cache.cfg','uid_cache.bin','extension_list.cfg')
    if any(p.startswith('.') for p in parts):return False
    if relative.suffix.lower() in ('.o','.obj','.a','.pdb','.log','.tmp','.pyc','.bak'):return False
    if target=='linux-x86_64' and relative.suffix.lower()=='.dll':return False
    if target=='windows-x86_64' and relative.suffix.lower()=='.so':return False
    if parts[:2]==('addons','godot-steam-audio') and target=='windows-x86_64':return False
    return True


PREFLIGHT = '''extends Node
func _enter_tree():
 if not OS.get_cmdline_user_args().has("--package-preflight"): return
 var ok = bool(ProjectSettings.get_setting("audio/driver/enable_input",false))
 if not ok: push_error("Packaged voice capture is disabled")
 var classes = ["SwgFirstPersonController", "SwgMeshBuilder", "SwgCombatCollision", "SwgVehicleControls", "SwgSnapshotMotion"]
 for name in classes:
  if not ClassDB.class_exists(name):
   push_error("Missing packaged native class: "+name)
   ok = false
 var planets = JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/planets/catalog.json"))
 if not planets is Dictionary:
  push_error("Sibling original ground-planet catalogue did not load")
  ok = false
 var ships = JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/jtl/catalog.json"))
 var ship_descriptors = 0
 if ships is Dictionary and ships.get("templates") is Dictionary:
  for row in ships.templates.values():
   for field in ["descriptor", "exterior_descriptor"]:
    if row.has(field):
     var descriptor = JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/jtl/"+str(row[field])))
     if descriptor is Dictionary: ship_descriptors += 1
     else: ok = false
 else:
  ok = false
 if ship_descriptors < 3:
  push_error("Original yacht and small-ship descriptors did not load")
  ok = false
 var presentation = JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/space_effects/assets.json"))
 var audio = JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/space_audio/catalog.json"))
 if not presentation is Dictionary or presentation.get("seat_poses",{}).size()!=20 or not audio is Dictionary or audio.get("sectors",{}).size()!=10:
  push_error("Matching presentation data with chair poses and space audio is required")
  ok = false
 var main_script = load("res://scripts/main.gd")
 var ground = JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/combat_actions/catalog.json"))
 if not ground is Dictionary or ground.get("schema",0)!=2 or str(ground.get("revision","")).length()!=64 or ground.get("templates",{}).is_empty():
  push_error("Matching prepared ground-combat profiles are required")
  ok = false
 if main_script == null:
  push_error("Packaged main script did not load")
  ok = false
 var apparel = check_apparel()
 ok = ok and apparel.passed
 print("SWGXR_PACKAGE_PREFLIGHT=",JSON.stringify({"apparel":apparel,"passed":ok,"native_classes":classes,"external_catalogue":planets is Dictionary,"ship_descriptors":ship_descriptors,"renderer":"dummy","xr":false}))
 get_tree().quit(0 if ok else 2)

func check_apparel() -> Dictionary:
 var result = {"passed":true,"cases":[]}
 var avatar = load("res://scripts/avatar.gd").new()
 add_child(avatar)
 # Cover starter catalogue paths and prepared inventory-variant paths in the
 # actual export template; source/editor runs do not reproduce path resolution.
 for race in ["rodian_male", "human_male"]:
  var configured = avatar.configure(race,{},[])
  var equipment = []
  for item in avatar.race.get("profession_outfits",{}).get("combat_marksman",[]):
   equipment.append({"id":str(equipment.size()),"template":item.get("template",""),"shared_template":item.get("shared_template",item.get("template",""))})
  var skeleton = avatar.skeleton
  avatar.set_tracking_mode(true)
  var refreshed = avatar.refresh_equipment(equipment)
  var visible = 0
  for mesh in avatar.meshes:
   if mesh.visible and mesh.get_meta("scope","")=="equipment": visible += 1
  var passed = str(configured.get("error","")).is_empty() and equipment.size()>0 and refreshed.get("complete",false) and refreshed.get("skinned_items",0)==equipment.size() and visible>0 and avatar.skeleton==skeleton and avatar.catalog_directory.is_absolute_path()
  result.cases.append({"race":race,"passed":passed,"refresh":refreshed,"visible_meshes":visible})
  result.passed = result.passed and passed
 avatar.free()
 return result
'''


def export_client(output, target):
    windows = target == "windows-x86_64"
    label = "Windows" if windows else "Linux"
    executable = "godot.exe" if windows else "godot"
    template=Path.home()/'.local/share/godot/export_templates/4.7.2.stable'/('windows_release_x86_64.exe' if windows else 'linux_release.x86_64')
    presets='[preset.0]\nname="Linux"\nplatform="Linux"\nrunnable=true\nexport_filter="all_resources"\ninclude_filter="*.json"\nexclude_filter="native/src/*,native/SConstruct,native/build_profile.json"\nexport_path=""\n[preset.0.options]\ncustom_template/release='+json.dumps(str(template))+'\nbinary_format/embed_pck=false\ntexture_format/bptc=true\ntexture_format/s3tc=true\n'
    if windows:
        presets=presets.replace('name="Linux"', 'name="Windows"').replace('platform="Linux"', 'platform="Windows Desktop"')
    (output/'client/export_presets.cfg').write_text(presets)
    (output/'client/package_preflight.gd').write_text(PREFLIGHT)
    project=output/'client/project.godot'
    project.write_text(project.read_text().replace('[autoload]\n','[autoload]\nPackagePreflight="*res://package_preflight.gd"\n'))
    evidence=ROOT/'runtime/evidence/test-client';evidence.mkdir(parents=True,exist_ok=True)
    command=['godot','--headless','--xr-mode','off','--audio-driver','Dummy','--path',str(output/'client'),'--export-release',label,str(output/'engine'/executable)]
    with (evidence/(target+'-export.log')).open('w') as log:
        result=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=300)
    if result.returncode!=0 or not (output/'engine/godot.pck').is_file():raise ValueError(target+' Godot export failed; inspect runtime/evidence/test-client/'+target+'-export.log')
    # Remove editor-only data generated by the export pass from the loose source.
    for path in sorted((output/'client/.godot').rglob('*'),reverse=True):
        if path.is_file() and not included(path.relative_to(output/'client'),target):path.unlink()
        elif path.is_dir() and not any(path.iterdir()):path.rmdir()
    (output/'client/export_presets.cfg').unlink()
    return command


def preflight_client(output, target, assets=None):
    windows=target=="windows-x86_64"
    output=Path(output).resolve();asset_link=output/'runtime/assets'
    if asset_link.exists():raise ValueError('Preflight expects code-only package runtime')
    evidence=ROOT/'runtime/evidence/test-client';evidence.mkdir(parents=True,exist_ok=True)
    asset_link.symlink_to(Path(assets).resolve() if assets else ROOT/'runtime/assets',target_is_directory=True)
    try:
        command=(["wine"] if windows else [])+[str(output/'engine'/('godot.exe' if windows else 'godot')),'--headless','--xr-mode','off','--audio-driver','Dummy','--log-file',str(evidence/(target+'-preflight-godot.log')),'--quit-after','5','--','--package-preflight']
        if windows:
            log_index=command.index('--log-file')+1
            command[log_index]='Z:'+command[log_index]
        try:
            import os
            env=os.environ.copy()
            if windows: env.update(WINEPREFIX=str(ROOT/'runtime/toolchains/wine-swgxr'),WINEDEBUG='-all')
            result=subprocess.run(command,cwd=output/'engine',capture_output=True,text=True,timeout=120,env=env)
        except subprocess.TimeoutExpired as exc:
            raw=(exc.stdout or b'')+(exc.stderr or b'')
            (evidence/(target+'-preflight.log')).write_text(raw.decode(errors='replace') if isinstance(raw,bytes) else raw)
            raise ValueError(target+' preflight timed out') from exc
        (evidence/(target+'-preflight.log')).write_text(result.stdout+result.stderr)
        passed=result.returncode==0 and '"passed":true' in result.stdout and 'SCRIPT ERROR' not in result.stderr
        report=dict(passed=passed,execution_environment='Wine on Linux' if windows else 'Linux',native_windows_validated=False,command=command,cwd=str(output/'engine'),renderer='dummy',xr_launched=False,original_assets_temporarily_linked_for_check=True,assets_in_package=False,returncode=result.returncode)
        (evidence/(target+'-preflight.json')).write_text(json.dumps(report,indent=2)+'\n')
        if not passed:raise ValueError(target+' preflight failed; inspect runtime/evidence/test-client/'+target+'-preflight.log')
        return report
    finally:asset_link.unlink()


def package(output,target,origin,ca,allow_incomplete=False,release_version=None):
    if target not in TARGETS:raise ValueError('Unsupported target')
    if release_version is not None and not re.fullmatch(r'v\d{4}\.\d{2}\.\d{2}-test\.\d+',release_version):raise ValueError('Invalid release version')
    if not re.fullmatch(r'https://[A-Za-z0-9][A-Za-z0-9.-]*(?::[0-9]{1,5})?',origin):raise ValueError('Expected public HTTPS server origin')
    ca=Path(ca).resolve();certificate=ca.read_bytes()
    if b'PRIVATE KEY' in certificate:raise ValueError('Only a public CA certificate may be packaged')
    ssl.create_default_context(cafile=str(ca))
    output=Path(output).resolve()
    if output.exists():raise ValueError('Output already exists')
    windows=target=='windows-x86_64';native=ROOT/'client/native/bin'/('libswg_native.dll' if windows else 'libswg_native.so')
    missing=[] if native.is_file() else [str(native.relative_to(ROOT))]
    if missing and not allow_incomplete:raise ValueError('Missing native library: '+', '.join(missing))
    output.mkdir(parents=True)
    try:
        for source in sorted((ROOT/'client').rglob('*')):
            relative=source.relative_to(ROOT/'client')
            if source.is_symlink():raise ValueError('Unexpected client symlink: '+str(relative))
            if not source.is_file() or not included(relative,target):continue
            destination=output/'client'/relative;destination.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,destination)
        extension_list=output/'client/.godot/extension_list.cfg'
        if windows and extension_list.is_file():extension_list.write_text('\n'.join(line for line in extension_list.read_text().splitlines() if 'godot-steam-audio' not in line)+'\n')
        engine=output/'engine';engine.mkdir()
        executable='godot.exe' if windows else 'godot'
        engine_source=Path.home()/'.local/share/godot/export_templates/4.7.2.stable'/('windows_release_x86_64.exe' if windows else 'linux_release.x86_64')
        shutil.copy2(engine_source.resolve(),engine/executable)
        shutil.copytree(ROOT/'runtime/releases/client-payload-20261008/engine/licenses',engine/'licenses')
        for source,name in [('test_client_launcher.py','test_client_launcher.py'),('update_test_client.py','update_test_client.py'),('tester_data.py','tester_data.py'),('start_test_client.py','start_client.py')]:shutil.copy2(ROOT/'tools/client'/source,output/name)
        (output/'engine/character_export').mkdir()
        for name in ('export_character.py','vrm.py','launcher.py','README.md'):
            shutil.copy2(ROOT/'tools/character_export'/name,output/'engine/character_export'/name)
        shutil.copy2(ca,output/'server-ca.pem')
        (output/'server.json').write_text(json.dumps({'base_url':origin},indent=2)+'\n')
        (output/'data').mkdir();(output/'runtime').mkdir()
        (output/'data/DROP-DATA-HERE.txt').write_text('Place all five SWG The Total Experience ISO images here. Alternatively select a local game installation in the launcher.\nPreparation reads local media, retains source archives for future updates and creates runtime/assets beside client/.\nThis folder intentionally ships empty of original SWG data.\n')
        try: from .package_data_preparation import package as package_recipe
        except ImportError: from package_data_preparation import package as package_recipe
        preparation_recipe=package_recipe(output/'engine/data-preparation')
        runnable=not missing
        python_runtime=None
        if windows:
            python_runtime=windows_python.install(output/'python')
            windows_python.write_launchers(output)
        else:
            for name, argument in (('play-vr.sh',''),('play-desktop.sh','--desktop '),('import-data.sh','--import-only '),('launcher.sh','--launcher '),('install-shortcuts.sh','--install-shortcuts '),('updates.sh','--launcher --updates ')):
                (output/name).write_text('#!/bin/sh\nset -eu\ncd -- "$(dirname -- "$0")"\nexec python3 start_client.py '+argument+'"$@"\n')
                (output/name).chmod(0o755)
        try: from .package_preparation_runtime import package as package_preparation_runtime
        except ImportError: from package_preparation_runtime import package as package_preparation_runtime
        package_preparation_runtime(output,target)
        requirements=('Windows x86_64, Vulkan graphics drivers and an OpenXR runtime. A private Python runtime, Windows native libraries and PCK are included; no Python installation, py launcher or developer tools are needed. Automated execution was checked through Wine on Linux; Windows Vulkan/OpenXR headset testing remains pending. Standard spatial audio fallback is used on Windows.\n' if windows else 'Linux x86_64, Python 3.10+ with Tk (python3-tkinter on Fedora; python3-tk on Debian/Ubuntu), glibc 2.43+, libstdc++ providing GLIBCXX_3.4.30, Vulkan graphics drivers and SteamVR or WiVRn configured as OpenXR runtime. Older Linux C libraries are unsupported.\n')
        (output/'START-HERE.txt').write_text('SWGXR test client — '+target+'\n\nRequires '+requirements+'\n1. Extract this client to a short, writable folder (Windows example: C:\\SWGXR).\n2. Put all five SWG The Total Experience ISO images in data/, or use Prepare game data in the launcher to select your installed game folder. Original assets are prepared locally; no private data ZIP is needed.\n3. Run '+('play-vr.cmd' if windows else './play-vr.sh')+' to enter VR. Use play-desktop for explicit desktop regression mode, or import-data to install data without launching.\n4. Run install-shortcuts'+('.cmd' if windows else '.sh')+' to add desktop icons. The SWGXR icon opens the desktop launcher; SWGXR Updates downloads and verifies the latest client, preserving assets and settings. Close the game before updating. No manual extraction is needed for subsequent updates.\nFirst preparation can take a while. Allow at least 40 GB free for sources, conversion and rollback data. Preparation resumes completed steps after interruption.\n\nCreate a new account in the sign-in panel. Existing accounts from the current realm are preserved.\nOnly the public server address and CA certificate are included. No account credentials are bundled. Original user-supplied SWG data stays on your computer and is never downloaded by the launcher.\nDo not move the client folder after importing data; extract a fresh client folder to relocate.\nScope: ten original ground planets and ten original JtL sectors, original hostile NPC encounters, pilot missions, Shipwright experimentation, hull redemption and components. The Luxury Yacht is excluded from combat. Space mining is deferred. See JTL_TEST_STATUS.md for missing media, pilot progression validation and presentation limits. Forward+ Vulkan only.\n')
        for name in ('TESTER_INSTALL.md','JTL_TEST_STATUS.md'):
            shutil.copy2(ROOT/'docs'/name,output/name)
        (output/'engine/docs').mkdir()
        for name in ('MEDIA_SCOPE.md','ORIGINAL_AUDIO.md'):
            shutil.copy2(ROOT/'docs'/name,output/'engine/docs'/name)
        # Linux editor needs its host libraries during Windows resource import.
        host_libraries=[]
        if windows:
            for source in (ROOT/'client').rglob('*.so'):
                if 'godot-steam-audio' in source.parts or 'build' in source.parts: continue
                destination=output/'client'/source.relative_to(ROOT/'client')
                destination.parent.mkdir(parents=True,exist_ok=True)
                shutil.copy2(source,destination);host_libraries.append(destination)
        export_client(output,target)
        for path in host_libraries:path.unlink()
        preflight_client(output,target)
        files=[]
        for source in sorted(output.rglob('*')):
            if source.is_file():files.append({'path':source.relative_to(output).as_posix(),'bytes':source.stat().st_size,'sha256':sha(source)})
        report=dict(schema=1,release_version=release_version,source_commit=subprocess.check_output(["git","rev-parse","HEAD"],cwd=ROOT,text=True).strip(),target=target,runnable=runnable,engine=executable,engine_uses_pck=True,working_directory='engine',linux_glibc_minimum='2.43' if not windows else None,linux_glibcxx_minimum='3.4.30' if not windows else None,original_data_included=False,credentials_included=False,missing=missing,files=files)
        if python_runtime:report['python_runtime']=python_runtime
        (output/'PACKAGE.json').write_text(json.dumps(report,indent=2)+'\n')
        return report
    except BaseException:
        shutil.rmtree(output);raise


def archive(folder,target):
    folder=Path(folder)
    destination=Path(str(folder)+('.zip' if target=='windows-x86_64' else '.tar.gz'))
    if destination.exists():raise ValueError('Archive already exists')
    if target=='windows-x86_64':
        with zipfile.ZipFile(destination,'x',zipfile.ZIP_DEFLATED,compresslevel=6) as output:
            for source in sorted(folder.rglob('*')):
                if source.is_file():output.write(source,folder.name+'/'+source.relative_to(folder).as_posix())
    else:
        with tarfile.open(destination,'w:gz',compresslevel=6) as output:output.add(folder,arcname=folder.name)
    Path(str(destination)+'.sha256').write_text(sha(destination)+'  '+destination.name+'\n')
    return destination

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--target',choices=TARGETS,required=True);parser.add_argument('--output',type=Path,required=True);parser.add_argument('--origin',required=True);parser.add_argument('--ca',type=Path,required=True);parser.add_argument('--allow-incomplete',action='store_true');parser.add_argument('--archive',action='store_true');parser.add_argument('--release-version')
    args=vars(parser.parse_args());compressed=args.pop('archive');result=package(**args)
    output=archive(args['output'],args['target']) if compressed else args['output']
    print(json.dumps({'output':str(output),'target':result['target'],'runnable':result['runnable'],'missing':result['missing'],'files':len(result['files'])}))
