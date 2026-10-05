#!/usr/bin/env python3
"""Export supplied SWG skill trees to ignored local assets; no skill grants."""
import json
from pathlib import Path
import sys
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from server.profession_catalog import catalog

if __name__ == '__main__':
    data = catalog()
    output = ROOT/'runtime/assets/professions/catalog.json'
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(data, indent=2)+'\n')
    print(json.dumps({'professions':len(data['professions']), 'nodes':sum(len(p['nodes']) for p in data['professions']), 'output':str(output)}))
