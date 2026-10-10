#!/usr/bin/env python3
"""Original GameMusicManager event banks from user-provided TREs."""
import json
from pathlib import Path
from prepare_environment import EnvironmentImporter
from swg_formats import parse_iff,cstring
from character_formats import datatable
ROOT=Path(__file__).resolve().parents[2]

def prepare():
    out=ROOT/'runtime/assets/game_audio';imp=EnvironmentImporter(ROOT/'runtime/asset_sources/active_tre',out)
    tree=parse_iff(imp.read('scene/game_music_manager.iff'))
    roles={'ENTR':'enter','EXIT':'exit','INCP':'incapacitated','DETH':'dead','WATR':'water','SENT':'space_enter','SEXI':'space_exit'}
    cues={role:[sound for n in tree.walk(tag) if (sound:=imp.sound(cstring(n.data)[0]))] for tag,role in roles.items()}
    ui={row['name']:imp.sound(row['path']) for row in datatable(imp.read('datatables/player/sounds.iff'))}
    result=dict(schema_version=1,cues=cues,ui=ui,sounds=imp.sounds,provenance=imp.dependencies,failures=imp.failures,
                reference='SWG-Source/client-tools@949451032647e45e42c3aaef3f41b132c8af36e3 GameMusicManager.cpp: state transitions and original GMUS banks',
                policy='Native player posture and combat transitions. Original recordings; no synthetic substitutes. Environment family/interior/day music handled by environment catalog.')
    (out/'catalog.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({'cues':{k:len(v) for k,v in cues.items()},'sounds':len(imp.sounds),'failures':imp.failures}))
if __name__=='__main__':prepare()
