#!/usr/bin/env python3
"""Refresh source alpha intent in cached static meshes, preserving geometry.

Run after conversion, or --ensure on launch. Does not synthesize opacity from
texture pixels: many opaque SWG textures use alpha for specular masks.
"""
from pathlib import Path
import argparse, hashlib, json
from swg_formats import TreSet, parse_iff
from shader_alpha import shader_alpha, SCHEMA_VERSION

ROOT=Path(__file__).resolve().parents[2]
ASSETS=ROOT/'runtime/assets'

def candidates(root):
    files=set()
    for directory in root.rglob('*'):
        if directory.is_dir() and directory.name in ('meshes','models'):
            files.update(directory.glob('*.json'))
    for name in ('mos_eisley/scene.json',):
        if (root/name).exists():files.add(root/name)
    return sorted(files)

def signature(paths,archives):
    rows=[(str(p),p.stat().st_size,p.stat().st_mtime_ns) for p in paths+sorted(archives.glob('*.tre'))]
    code=b''.join(p.read_bytes() for p in (Path(__file__),Path(__file__).with_name('shader_alpha.py')))
    return hashlib.sha256(code+json.dumps(rows).encode()).hexdigest()

def refresh_model_references(root, changes):
    """Carry verified before/after hashes into catalogs referencing edited models.

    Only replace the exact pre-edit hash; an unrelated mismatch must still fail
    provenance validation. Model geometry and source hashes are untouched.
    """
    updated=[]
    for path in sorted(root.rglob('catalog.json')):
        value=json.loads(path.read_text());modified=False
        def visit(node):
            nonlocal modified
            if isinstance(node,dict):
                for file_key,hash_key in (('model','model_sha256'),('preview_model','preview_sha256'),('source_model','source_model_sha256')):
                    if not isinstance(node.get(file_key),str) or hash_key not in node:continue
                    base=root/'inventory' if file_key=='preview_model' and path.parent.name=='gcw' else path.parent
                    source=(base/node[file_key]).resolve()
                    change=changes.get(source)
                    if change and node[hash_key]==change[0]:
                        node[hash_key]=change[1];modified=True
                for child in node.values():visit(child)
            elif isinstance(node,list):
                for child in node:visit(child)
        visit(value)
        if modified:
            temp=path.with_suffix('.json.material.tmp');temp.write_text(json.dumps(value,indent=2)+'\n');temp.replace(path)
            updated.append(str(path.relative_to(root)))
    return updated

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--ensure',action='store_true');parser.add_argument('--assets',type=Path,default=ASSETS);args=parser.parse_args()
    root=args.assets;paths=candidates(root);archives=ROOT/'runtime/asset_sources/active_tre';stamp=ROOT/'runtime/asset_reports/static_material_state.json'
    stamp.parent.mkdir(parents=True,exist_ok=True)
    current=signature(paths,archives)
    previous=json.loads(stamp.read_text()) if stamp.exists() else {}
    if args.ensure and previous.get('signature')==current and previous.get('failures',1)==0:
        print('Original static material alpha metadata is current.');return
    tre=TreSet(archives);dependencies={};cache={};materials={};failures=[];changed=[];classification=[];surface_count=0
    def read(name):
        raw=tre.read(name);dependencies[name]={'archive':tre.entries[name][0].name,'sha256':hashlib.sha256(raw).hexdigest(),'bytes':len(raw)};return raw
    def visit(value,path):
        nonlocal surface_count
        modified=False
        if isinstance(value,dict):
            if all(k in value for k in ('vertices','indices','shader')):
                # Static top-level mesh records and the retained stage only;
                # skeletal parts carry bones/weights and have their own pipeline.
                if 'bones' in value or 'weights' in value:return False
                name=value['shader'];surface_count+=1
                try:
                    if name not in materials:materials[name]=shader_alpha(parse_iff(read(name)),read,cache)
                    update=materials[name]
                    if bool(value.get('alpha',False))!=update['alpha']:classification.append({'file':str(path.relative_to(root)),'shader':name,'before':bool(value.get('alpha',False)),'after':update['alpha']})
                    if any(value.get(k)!=v for k,v in update.items()):value.update(update);modified=True
                except Exception as error:
                    if not any(f['shader']==name for f in failures):failures.append({'shader':name,'error':str(error)})
            else:
                for child in value.values():modified=visit(child,path) or modified
        elif isinstance(value,list):
            for child in value:
                if isinstance(child,(dict,list)):modified=visit(child,path) or modified
        return modified
    hash_changes={}
    for path in paths:
        before=path.read_bytes();value=json.loads(before)
        # Avoid descending through large skeletal animation/bone arrays.
        if not isinstance(value,dict) or not ('surfaces' in value or path.name=='scene.json'):continue
        if visit(value,path):
            after=json.dumps(value,separators=(',',':')).encode()
            temporary=path.with_suffix('.json.material.tmp');temporary.write_bytes(after);temporary.replace(path);changed.append(str(path.relative_to(root)))
            hash_changes[path.resolve()]=(hashlib.sha256(before).hexdigest(),hashlib.sha256(after).hexdigest())
    updated_catalogs=refresh_model_references(root,hash_changes)
    report={'schema_version':SCHEMA_VERSION,'files_checked':len(paths),'static_surfaces':surface_count,'updated_files':changed,'classification_changes':classification,'failures':failures,'dependencies':dependencies,'geometry_modified':False}
    report['updated_catalogs']=updated_catalogs
    (ROOT/'runtime/asset_reports/static_material_report.json').write_text(json.dumps(report,indent=2))
    stamp.write_text(json.dumps({'schema_version':SCHEMA_VERSION,'signature':signature(paths,archives),'failures':len(failures)},indent=2))
    print(json.dumps({'updated_files':len(changed),'classification_changes':len(classification),'failures':len(failures),'geometry_modified':False}))
    if failures:raise SystemExit(1)

if __name__=='__main__':main()
