#!/usr/bin/env python3
"""Export original local SWG datapad UI, bitmap fonts, planet map and reference POIs.

This catalog grants no objects. Player datapad contents must come from Core3.
"""
import argparse, hashlib, io, json, re, struct
from html.parser import HTMLParser
from pathlib import Path
from PIL import Image
from swg_formats import TreSet, parse_iff, cstring
from prepare_environment import snapshot
from character_formats import datatable
from stf import string_table
ROOT = Path(__file__).resolve().parents[2]
SOURCE_REVISION = '949451032647e45e42c3aaef3f41b132c8af36e3'
MAP_SOURCE = f'https://github.com/SWG-Source/client-tools/blob/{SOURCE_REVISION}/src/game/client/library/swgClientUserInterface/src/shared/page/SwgCuiPlanetMap.cpp'

class Elements(HTMLParser):
    def __init__(self, text):
        super().__init__(); self.items=[]; self.feed(text)
    def handle_starttag(self, tag, attrs): self.items.append((tag, dict(attrs)))
    def handle_startendtag(self, tag, attrs): self.handle_starttag(tag, attrs)

class Importer:
    def __init__(self, tre, out):
        self.t=TreSet(tre);self.out=out;out.mkdir(parents=True,exist_ok=True)
        self.dependencies={};self.tables={}
    def read(self,path):
        raw=self.t.read(path);self.dependencies[path]={'archive':self.t.entries[path][0].name,'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest()};return raw
    def label(self, ref):
        if not ref.startswith('@'):return ref
        key=ref[1:];table,name=key.split(':',1) if ':' in key else ('ui',key)
        if table not in self.tables:self.tables[table]=string_table(self.read('string/en/'+table+'.stf'))
        return self.tables[table].get(name,ref)
    def image(self, source, relative):
        im=Image.open(io.BytesIO(self.read(source))).convert('RGBA');dest=self.out/relative;dest.parent.mkdir(parents=True,exist_ok=True);im.save(dest)
        return {'texture':relative,'source':source,'width':im.width,'height':im.height}
    def font(self,name):
        source='ui/font/'+name+'.inc';items=Elements(self.read(source).decode()).items
        style=next(a for t,a in items if t=='textstyle');height=int(style['leading']);glyphs=[a for t,a in items if t=='fontcharacter'];pages={};records=[]
        for glyph in glyphs:
            texture=glyph['sourcefile']
            if texture not in pages:
                pages[texture]=self.image('texture/'+texture+'.dds','fonts/'+texture.rsplit('/',1)[-1]+'.png')
            rect=list(map(int,glyph['sourcerect'].split(',')));code=int(glyph.get('code',str(int(glyph['name'],16))))
            records.append({'id':code,'x':rect[0],'y':rect[1],'width':rect[2]-rect[0],'height':rect[3]-rect[1],'xoffset':int(glyph.get('advancepre',0)),'yoffset':0,'xadvance':int(glyph['advance']),'page':list(pages).index(texture),'chnl':15})
        first=next(iter(pages.values()));lines=[f'info face="{name}" size={height} bold={int("bold" in name)} italic=0 charset="" unicode=1 stretchH=100 smooth=0 aa=1 padding=0,0,0,0 spacing=0,0',f'common lineHeight={height} base={height} scaleW={first["width"]} scaleH={first["height"]} pages={len(pages)} packed=0']
        lines += [f'page id={i} file="{Path(p["texture"]).name}"' for i,p in enumerate(pages.values())]
        lines += [f'chars count={len(records)}']+['char '+' '.join(f'{k}={v}' for k,v in g.items()) for g in records]
        dest='fonts/'+name+'.fnt';(self.out/dest).write_text('\n'.join(lines)+'\n')
        return {'id':name,'path':dest,'source':source,'line_height':height,'glyph_count':len(records),'pages':list(pages.values()),'format':'AngelCode BMFont text converted from original FontCharacter metrics','license':'Original SWG game font atlas supplied by user; proprietary provenance, no redistribution license asserted. Font family Verdana.','baseline_policy':'Original line top retained; BMFont baseline set to source Leading because source does not expose a separate baseline.'}

from planet_config import PLANETS

def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--tre-dir',type=Path,default=ROOT/'runtime/asset_sources/active_tre');ap.add_argument('--out',type=Path,default=ROOT/'runtime/assets/datapad');ap.add_argument('--core3-root',type=Path,default=ROOT/'vendor/Core3');args=ap.parse_args();imp=Importer(args.tre_dir,args.out)
    layout='ui/ui_pda_data_storage.inc';items=Elements(imp.read(layout).decode()).items
    categories=[{'id':a['name'].replace('@datapad_tab_',''),'label':imp.label(a['name']),'label_source':a['name'],'target':a['target']} for t,a in items if t=='data' and a.get('name','').startswith('@datapad_tab_')]
    help_table=string_table(imp.read('string/en/ui_datapad.stf'))
    icons={}
    for name in ['you','generic','cloning','cantina','waypoint','guild','theme','starport','shuttleport','hotel','city','bank','hospital']:
        image=imp.image('texture/ui_marker_'+name+'.dds','icons/'+name+'.png');image.update(uv_rect=[0,0,image['width'],image['height']],uv_units='pixels');icons[name]=image
    imp.read('ui/ui_styles.inc');imp.read('ui/ui_planet_map.inc')
    poi_source='datatables/clientpoi/clientpoi.iff';pois=[]
    for row in datatable(imp.read(poi_source)):
        pois.append({'id':row['Name'],'name':imp.label(row['Name']),'description':imp.label(row['Description']),'planet':row['Planet'],'position':[row['X'],row['Y'],row['Z']],'type':'poi','icon':'generic','appearance':row['Appearance'],'source':poi_source})
    maps={};external={}
    for zone in PLANETS:
        planet=imp.image(f'texture/ui_map_{zone}.dds',f'maps/{zone}.png')
        landmarks=[p for p in pois if p['planet']==zone]
        regions=args.core3_root/f'MMOCoreORB/bin/scripts/managers/planet/{zone}_regions.lua'
        if regions.exists():
            raw=regions.read_bytes();external[str(regions.relative_to(args.core3_root))]={'sha256':hashlib.sha256(raw).hexdigest(),'source':'Core3 checked-out source file'}
            for line_no,line in enumerate(raw.decode().splitlines(),1):
                match=re.search(r'\{"(@[a-z0-9]+_region_names:[^"]+)"\s*,\s*([-\d.]+)\s*,\s*([-\d.]+)',line)
                if match and re.search(r'\bCITY\b',line):
                    ref,x,z=match.groups();landmarks.append({'id':ref,'name':imp.label(ref),'position':[float(x),0,float(z)],'type':'city','icon':'city','source':str(regions.relative_to(args.core3_root)),'source_line':line_no})
        # Locations come from the original world snapshot, never estimated city offsets.
        for node in snapshot(imp,zone):
            template=node['template']
            if not template.startswith('object/building/'):continue
            kind=next((k for k in ['starport','shuttleport','cantina','bank','hospital','cloning'] if k in template),'')
            if not kind:continue
            label=kind.title();label_source=''
            for entry in parse_iff(imp.read(template)).walk('XXXX'):
                if entry.data.startswith(b'objectName\0\1\1'):
                    table,pos=cstring(entry.data,len(b'objectName\0\1\1'));key,_=cstring(entry.data,pos+1)
                    label_source='@'+table+':'+key;label=imp.label(label_source);break
            landmarks.append({'id':'snapshot:'+str(node['id']),'name':label,'label_source':label_source,'position':list(node['p']),'type':kind,'icon':kind,'source':f'snapshot/{zone}.ws','source_object_id':node['id'],'source_template':template,'classification':'Map icon selected from explicit source building template family.'})
        planet.update(world_bounds=[-8192,-8192,8192,8192],image_top='north/+Z',image_right='+X',coordinate_system='SWG world XYZ; image u=(x+8192)/16384, v=(8192-z)/16384',landmarks=landmarks,transform_source={'url':MAP_SOURCE,'revision':SOURCE_REVISION,'lines':[134,1105,1106,1107],'limitation':'Source revision corroborates coordinate convention; map artwork and POIs are from supplied pre-CU TRE archives.'})
        maps[zone]=planet
    waypoint_colors=datatable(imp.read('datatables/player/waypoint_map.iff'))
    map_categories=datatable(imp.read('datatables/player/planet_map_cat.iff'))
    fonts=[imp.font(n) for n in ['verdana_18','verdana_bold_18','verdana_bold_24']]
    previews={'datapad':'appearance/eqp_datapad_s2_inventory.apt','waypoint':'appearance/ui_datapad_waypoint.apt'}
    for path in previews.values():imp.read(path)
    baseline_sources={}
    for relative in ['MMOCoreORB/bin/scripts/managers/player_creation_manager.lua','MMOCoreORB/src/server/zone/managers/player/creation/PlayerCreationManager.cpp','MMOCoreORB/src/server/zone/objects/player/events/SpawnHelperDroidTask.h','MMOCoreORB/src/server/zone/objects/creature/CreatureObjectImplementation.cpp']:
        path=args.core3_root/relative
        if path.exists():
            baseline_sources[relative]={'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
    catalog={'schema_version':1,'ui':{'title':imp.label('@datapad_title'),'source':layout,'categories':categories,'help':help_table,'fonts':fonts,'layout':{'structure':'Source tabs with icon/list container and selected-object preview/details pane; adapted layout is a client responsibility.','text_color':'#96F4FC','line_color':'#1CFFFF'}},'maps':maps,'icons':icons,'points_of_interest':pois,'waypoint_colors':waypoint_colors,'map_categories':map_categories,'preview_asset_refs':previews,'starter_contents':{'entries':[],'authority':'Core3 character datapad contents and waypoints API','baseline_audit':{'sources':baseline_sources,'finding':'Core3 commonStartingItems includes an X31 landspeeder deed; addStartingItems transfers common items into inventory (lines732-749), not an already-created datapad vehicle control device. SpawnHelperDroidTask can separately create a genuine helper R2 control device in the datapad after eligible starting skills, outside tutorial. Initial empty creation snapshots do not prove later character contents; use actual backend readback.','reference_template':'object/tangible/deed/vehicle_deed/landspeeder_x31_deed.iff'},'policy':'This reference catalog grants no pets, vehicles, schematics or items. POIs are shared client reference entries, not server-granted possessions.'},'provenance':{'assets':'User-supplied local original SWG archives; generated files must remain local/ignored.','dependencies':imp.dependencies,'external_sources':external},'limitations':['World map is the original 1024px planet overview; zoom does not create new detailed city imagery.','Source item preview references are metadata, not exported 3D meshes.','Bitmap fonts preserve source atlas glyphs and advance metrics; no vector font or license is bundled.']}
    preview_manifest=args.out/'previews/manifest.json'
    if preview_manifest.exists():catalog['template_previews']=json.loads(preview_manifest.read_text())
    (args.out/'catalog.json').write_text(json.dumps(catalog,indent=2)+'\n')
    print(json.dumps({'catalog':str(args.out/'catalog.json'),'categories':len(categories),'fonts':len(fonts),'icons':len(icons),'map_landmarks':{k:len(v['landmarks']) for k,v in maps.items()},'poi_total':len(pois),'dependencies':len(imp.dependencies)}))
if __name__=='__main__':main()
