#!/usr/bin/env python3
"""Verify converted source environment references, source hashes and Ogg audio."""
import argparse,concurrent.futures,hashlib,json,math,subprocess
from pathlib import Path
from swg_formats import TreSet
ROOT=Path(__file__).resolve().parents[2]

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--directory',type=Path,default=ROOT/'runtime/assets/tatooine_environment');args=p.parse_args();root=args.directory;manifest=json.loads((root/'environment.json').read_text());audio=set()
 assert manifest['default_family'] in manifest['families'] and manifest['cycle_seconds']>0
 for name,family in manifest['families'].items():
  assert len(family['lighting_samples'])==256,name
  for sample in family['lighting_samples']:
   for key in ('ambient','sun','sky_top','sky_horizon'):assert len(sample[key])==3 and all(math.isfinite(x) and 0<=x<=1 for x in sample[key]),(name,key)
  for role in ('day_ambient','night_ambient','day_ambient_secondary','night_ambient_secondary','first_music','sunrise_music','sunset_music'):
   if family.get(role):assert family[role] in manifest['sounds'],(name,role)
 for source,sound in manifest['sounds'].items():
  assert sound['samples'] and len(sound['samples'])==len(sound['sample_sources']),source
  assert 0<=sound['volume']<=1 and len(sound['source_numeric_tail_hex'])==224,source
  for relative in sound['samples']:assert (root/relative).is_file(),relative;audio.add(relative)
 for emitter in manifest['emitters']:
  assert emitter['sound'] in manifest['sounds'] and len(emitter['position'])==3 and all(math.isfinite(x) for x in emitter['position'])
 def probe(relative):
  r=subprocess.run(['ffprobe','-v','error','-show_entries','format=duration:stream=codec_name,sample_rate,channels','-of','json',str(root/relative)],capture_output=True,text=True);assert r.returncode==0,(relative,r.stderr);data=json.loads(r.stdout);duration=float(data['format']['duration']);assert math.isfinite(duration) and duration>0;assert all(s['codec_name']=='vorbis' for s in data['streams']);return duration
 with concurrent.futures.ThreadPoolExecutor(max_workers=8) as executor:durations=list(executor.map(probe,sorted(audio)))
 tre=TreSet(Path(manifest['provenance']['tre_directory']))
 for source,dependency in manifest['provenance']['dependencies'].items():assert hashlib.sha256(tre.read(source)).hexdigest()==dependency['sha256'],source
 print(json.dumps({'status':'passed','families':len(manifest['families']),'sounds':len(manifest['sounds']),'unique_audio_files':len(audio),'total_unique_audio_seconds':sum(durations),'emitters':len(manifest['emitters']),'verified_dependencies':len(manifest['provenance']['dependencies']),'source_failures':manifest['failures']},indent=2))
if __name__=='__main__':main()
