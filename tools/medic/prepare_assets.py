#!/usr/bin/env python3
"""Import original medical focus/stimpack geometry and source command icons."""
from pathlib import Path
import subprocess,sys
ROOT=Path(__file__).resolve().parents[2]
subprocess.run([sys.executable,str(ROOT/'tools/assets/prepare_inventory.py'),
 '--template','object/tangible/medicine/medikit_tool_basic.iff',
 '--template','object/tangible/medicine/medikit_tool_advanced.iff',
 '--template','object/tangible/medicine/stimpack_sm_s1.iff'],cwd=ROOT,check=True)
subprocess.run([sys.executable,str(ROOT/'tools/combat/prepare_abilities.py')],cwd=ROOT,check=True)
# Both importers retain archive hashes/failures in ignored runtime catalogs.
