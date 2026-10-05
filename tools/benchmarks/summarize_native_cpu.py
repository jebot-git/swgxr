#!/usr/bin/env python3
"""Summarize eu-stackprof leaf histograms as sample shares, never fake seconds."""
import argparse,bisect,collections,json,lzma,pathlib,re,struct,subprocess,sys
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('directory',type=pathlib.Path,help='Existing collect_native_cpu.py output directory.')
folder=parser.parse_args().directory
if not folder.is_dir(): parser.error('Collection directory does not exist.')
symdir=folder/'symbols';symdir.mkdir(exist_ok=True)
symbol_tables={}
module_by_path={}
def elf_sections(path):
 data=path.read_bytes()
 if data[:5]!=b'\x7fELF\x02' or data[5]!=1:return {},data
 h=struct.unpack_from('<16sHHIQQQIHHHHHH',data)
 sections=[struct.unpack_from('<IIQQQQIIQQ',data,h[6]+i*h[11]) for i in range(h[12])]
 ns=sections[h[13]]; strings=data[ns[4]:ns[4]+ns[5]]
 return {strings[s[0]:].split(b'\0')[0].decode():s for s in sections},data
def symbols(path,bid):
 if not path.is_file():return [],[],str(path)
 sections,data=elf_sections(path); image=path
 if '.symtab' not in sections and '.gnu_debugdata' in sections:
  s=sections['.gnu_debugdata'];mini=symdir/(bid+'.mini.elf');mini.write_bytes(lzma.decompress(data[s[4]:s[4]+s[5]]))
  image=symdir/(bid+'.elf')
  merged=subprocess.run(['eu-unstrip','-o',str(image),str(path),str(mini)],capture_output=True)
  if merged.returncode: image=mini
 command=['nm','-n','-S','--defined-only','--demangle',str(image)]
 if '.symtab' not in sections and '.gnu_debugdata' not in sections:command.insert(1,'-D')
 out=subprocess.run(command,capture_output=True,text=True).stdout
 entries=[]
 for line in out.splitlines():
  match=re.match(r'^([0-9a-fA-F]+)\s+([0-9a-fA-F]+)\s+([TtWwIi])\s+(.*)$',line)
  if match:entries.append((int(match[1],16),int(match[2],16),match[4]))
 entries.sort(); return [e[0] for e in entries],entries,str(image)
def histogram(path):
 data=path.read_bytes(); assert data[:4]==b'gmon';pos=20;result=collections.Counter()
 while pos<len(data):
  tag=data[pos];pos+=1
  if tag==0:
   lo,hi,n,rate=struct.unpack_from('<QQII',data,pos);pos+=40
   values=struct.unpack_from('<'+'H'*n,data,pos);pos+=2*n
   step=(hi-lo)//(n-1) if n>1 else 1
   for i,count in enumerate(values):
    if count:result[lo+i*step]+=count
  elif tag==1:pos+=20
  else:raise ValueError((path,tag,pos))
 return result
modules=[]; functions=collections.Counter(); total=0
for meta_file in sorted(folder.glob('gmon.*.json')):
 meta=json.loads(meta_file.read_text());bid=meta['buildid'];path=pathlib.Path(meta.get('mainfile','<unknown>'))
 hist=histogram(folder/('gmon.'+bid+'.out')); count=sum(hist.values());total+=count
 starts,entries,image=symbols(path,bid); local=collections.Counter()
 symbol_tables[str(path)]=(starts,entries)
 for pc,n in hist.items():
  i=bisect.bisect_right(starts,pc)-1; name='[unresolved 0x%x]'%pc
  if i>=0:
   start,size,candidate=entries[i]
   if start<=pc<start+max(size,1):name=candidate
  local[name]+=n;functions[(str(path),name)]+=n
 modules.append({'module':str(path),'build_id':bid,'samples':count,'symbol_image':image,'top_functions':[{'function':k,'samples':v} for k,v in local.most_common(30)]})

for m in modules:m['share_percent']=100*m['samples']/total if total else 0
result={'event':'cycles:u:period=20000000','sample_kind':'user-space CPU leaf samples; excludes kernel CPU and blocked/wait wall time','histogram_samples':total,'modules':sorted(modules,key=lambda m:-m['samples']),'top_functions':[{'module':m,'function':f,'samples':n,'share_percent':100*n/total} for (m,f),n in functions.most_common(60)],'limits':['Sample shares are not elapsed milliseconds or inclusive stack costs.','Profiler changes workload and must not be compared as normal-play frame timings.','Existing sibling threads are not collected by -p mainPID; future descendants inherit events.','Symbols come from shipped local ELF symtab/minidebug data, with unresolved addresses retained.','See collector log for unwind errors, lost samples, and actual event arguments.']}
# Optional inclusive attribution uses only already-captured stack snapshots.
# Counts overlap across modules/functions and are never added to leaf samples.
if (folder/'maps.txt').is_file() and (folder/'collector.log').is_file():
 ranges=[]
 for line in (folder/'maps.txt').read_text().splitlines():
  parts=line.split(None,5)
  if len(parts)>5:
   lo,hi=[int(x,16) for x in parts[0].split('-')]
   ranges.append((lo,hi,parts[5]))
 ranges.sort();range_starts=[row[0] for row in ranges]
 stack_modules=collections.Counter();stack_functions=collections.Counter();stack_count=0
 for block in (folder/'collector.log').read_text().split('find_dwfl ')[1:]:
  frames=re.findall(r'\* frame (\d+): rel_pc=([0-9a-f]+) raw_pc=([0-9a-f]+)',block)
  if not frames:continue
  stack_count+=1;seen_modules=set();seen_functions=set()
  for index,relative,raw in frames:
   addr=int(raw,16);region=bisect.bisect_right(range_starts,addr)-1
   if region<0 or addr>=ranges[region][1]:continue
   path=ranges[region][2];seen_modules.add(path)
   starts,entries=symbol_tables.get(path,([],[]));pc=int(relative,16)
   i=bisect.bisect_right(starts,pc)-1
   if i>=0 and entries[i][0]<=pc<entries[i][0]+max(entries[i][1],1):seen_functions.add((path,entries[i][2]))
  for path in seen_modules:stack_modules[path]+=1
  for key in seen_functions:stack_functions[key]+=1
 result['inclusive_stacks']={'samples':stack_count,'modules':[{'module':m,'samples':n,'percent':100*n/stack_count} for m,n in stack_modules.most_common()] if stack_count else [],'functions':[{'module':m,'function':f,'samples':n,'percent':100*n/stack_count} for (m,f),n in stack_functions.most_common(100)] if stack_count else [],'limits':'Inclusive appearances overlap across frames and modules; do not sum percentages. Truncated stacks can undercount callers.'}
(folder/'native-summary.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({'samples':total,'modules':[(m['module'],m['samples']) for m in result['modules']],'top':result['top_functions'][:12]},indent=2))
