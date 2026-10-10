#!/usr/bin/env python3
"""Import separately supplied data and start the explicitly selected test mode."""
import argparse
import json
import os
import platform
from pathlib import Path
import subprocess
import sys
import zipfile
try:
    from . import test_client_launcher as launcher
except ImportError:
    import test_client_launcher as launcher
try:
    from .tester_data import ensure_data
except ImportError:
    from tester_data import ensure_data


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--desktop',action='store_true',help='Explicit desktop regression mode; XR is disabled')
    parser.add_argument('--import-only',action='store_true')
    parser.add_argument('--launcher',action='store_true',help='Open the desktop launcher')
    parser.add_argument('--terminal-menu',action='store_true',help='Use the text menu instead of the desktop launcher')
    parser.add_argument('--game-installation',type=Path,help='Prepare from a local Total Experience installation; otherwise use five ISO images in data/')
    parser.add_argument('--prepare-game-data',action='store_true')
    parser.add_argument('--asset-archive',type=Path,help='Import a supplied asset ZIP from this location')
    parser.add_argument('--install-shortcuts',action='store_true')
    parser.add_argument('--updates',action='store_true')
    parser.add_argument('--export-character',action='store_true',help='Open the character-to-VRM exporter; does not launch VR')
    args=parser.parse_args();root=Path(__file__).resolve().parent
    try:
        if args.export_character:
            sys.path.insert(0,str(root/'engine'))
            from character_export.launcher import gui
            return gui(root)
        if args.launcher:
            return launcher.gui(root, update_on_open=args.updates)
        if args.install_shortcuts:
            launcher.install_shortcuts(root);return 0
        if args.updates:
            try: from .update_test_client import update
            except ImportError: from update_test_client import update
            update(root);return 0
        if args.terminal_menu:
            selected=launcher.menu(root)
            if selected is None:return 0
            args.desktop='--desktop' in selected
            args.import_only='--import-only' in selected
        try: from .update_test_client import installation_lock
        except ImportError: from update_test_client import installation_lock
        with installation_lock(root):
            state=json.loads((root/'PACKAGE.json').read_text())
            if not state['runnable']: raise ValueError('This is a Windows build handoff, not a runnable client. Read BUILD-WINDOWS.txt.')
            minimum=state.get('linux_glibc_minimum')
            if minimum:
                family,version=platform.libc_ver()
                if family!='glibc' or tuple(map(int,version.split('.'))) < tuple(map(int,minimum.split('.'))):raise ValueError('This Linux native build requires glibc '+minimum+' or later; detected '+family+' '+version)
            if args.asset_archive:
                try: from .tester_data import install
                except ImportError: from tester_data import install
                result=install(args.asset_archive,root)
                print('Assets ready: '+str(result['verified_files'])+' verified files.',flush=True)
            elif (root/'engine/data-preparation/recipe.json').is_file():
                executable=root/'python/python.exe' if os.name=='nt' else root/'engine/data-python/bin/python3'
                command=[str(executable),'-u',str(root/'engine/data-preparation/tools/client/prepare_game_data.py'),'--root',str(root)]
                if args.game_installation:command+=['--installation',str(args.game_installation)]
                subprocess.run(command,cwd=root,check=True)
            else:ensure_data(root)
            if args.import_only:return 0
            public=json.loads((root/'server.json').read_text());public['ca_certificate']=(root/'server-ca.pem').as_posix()
            runtime=root/'runtime/client';runtime.mkdir(parents=True,exist_ok=True)
            profile=runtime/'connection.json';profile.write_text(json.dumps(public)+'\n')
            command=[str(root/'engine'/state['engine']),'--rendering-method','forward_plus','--rendering-driver','vulkan']
            if args.desktop:command+=['--xr-mode','off']
            command+=['--','--connection-profile='+str(profile)]
            if args.desktop:command+=['--desktop']
            env=os.environ.copy();env.pop('OBS_VKCAPTURE',None);env.update(DISABLE_XR_APILAYER_NOVENDOR_OBSMirror='1',DISABLE_OBS_VKCAPTURE='1')
            return subprocess.run(command,cwd=root/state["working_directory"],env=env,check=False).returncode
    except (ValueError,OSError,KeyError,EOFError,subprocess.CalledProcessError,zipfile.BadZipFile) as exc:
        print('Cannot start SWGXR: '+str(exc),file=sys.stderr);return 2

if __name__=='__main__':raise SystemExit(main())
