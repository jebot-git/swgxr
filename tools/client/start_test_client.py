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
    parser.add_argument('--launcher',action='store_true')
    parser.add_argument('--install-shortcuts',action='store_true')
    parser.add_argument('--updates',action='store_true')
    args=parser.parse_args();root=Path(__file__).resolve().parent
    try:
        if args.install_shortcuts:
            launcher.install_shortcuts(root);return 0
        if args.updates:
            launcher.webbrowser.open(launcher.RELEASES);return 0
        if args.launcher:
            selected=launcher.menu(root)
            if selected is None:return 0
            args.desktop='--desktop' in selected
            args.import_only='--import-only' in selected
        state=json.loads((root/'PACKAGE.json').read_text())
        if not state['runnable']: raise ValueError('This is a Windows build handoff, not a runnable client. Read BUILD-WINDOWS.txt.')
        minimum=state.get('linux_glibc_minimum')
        if minimum:
            family,version=platform.libc_ver()
            if family!='glibc' or tuple(map(int,version.split('.'))) < tuple(map(int,minimum.split('.'))):raise ValueError('This Linux native build requires glibc '+minimum+' or later; detected '+family+' '+version)
        ensure_data(root)
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
