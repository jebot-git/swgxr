"""Small, read-only parsers for the supplied SWG TRE v5 and IFF resources.

Format references: SWGEmu Core3/Engine3; io_scene_swg (MIT, Nick Rafalski).
No original client implementation or asset data is included here.
"""
from pathlib import Path
from dataclasses import dataclass
import struct, zlib, re
from archive_policy import CORE3_TRE_PRIORITY

class TreSet:
    def __init__(self, directory):
        self.entries = {}
        self.archives = []
        paths = list(Path(directory).rglob('*.tre'))
        # Apply exactly the same precedence as the pinned Core3 configuration.
        # Unknown archives are allowed for explicit standalone inspection, below
        # known files; activation filters them with the pre-CU allowlist.
        def priority(p):
            if p.name in CORE3_TRE_PRIORITY:
                return (1,-CORE3_TRE_PRIORITY.index(p.name))
            return (0,p.name)
        for p in sorted(paths,key=priority):
            with p.open('rb') as f:
                assert f.read(8) == b'EERT5000', p
                count,offset,tc,ts,nc,ns,nlen = struct.unpack('<7I',f.read(28))
                f.seek(offset)
                toc=f.read(ts if tc else count*24)
                if tc: toc=zlib.decompress(toc)
                names=f.read(ns if nc else nlen)
                if nc:names=zlib.decompress(names)
                assert len(toc)==count*24 and len(names)==nlen
                for i in range(count):
                    crc,size,off,comp,csize,noff=struct.unpack_from('<6I',toc,i*24)
                    name=names[noff:names.index(0,noff)].decode('ascii').lower()
                    self.entries[name]=(p,off,size,comp,csize)
            self.archives.append(p)
    def read(self,name):
        p,off,size,comp,csize=self.entries[name.lower()]
        with p.open('rb') as f:
            f.seek(off); d=f.read(csize if comp else size)
        if comp:d=zlib.decompress(d)
        assert len(d)==size,(name,len(d),size)
        return d

@dataclass
class Iff:
    tag: str
    data: bytes
    children: list
    def walk(self,tag=None):
        if tag is None or self.tag==tag:yield self
        for child in self.children:yield from child.walk(tag)
    def first(self,tag):return next(self.walk(tag))

def parse_iff(data):
    def sequence(start,end):
        result=[]
        while start < end:
            if end-start < 8: raise ValueError(f'IFF truncated at {start}')
            tag=data[start:start+4].decode('ascii')
            n=struct.unpack_from('>I',data,start+4)[0]
            stop=start+8+n
            if stop>end:raise ValueError(f'IFF bounds {tag}')
            if tag=='FORM':
                node=Iff(data[start+8:start+12].decode('ascii'),b'',sequence(start+12,stop))
            else:node=Iff(tag,data[start+8:stop],[])
            result.append(node);start=stop
        return result
    return sequence(0,len(data))[0]

def cstring(data,start=0):
    stop=data.index(0,start)
    return data[start:stop].decode('ascii'),stop+1

def refs(data):
    return [x.decode('ascii') for x in re.findall(rb'[a-zA-Z0-9_./-]+\.(?:msh|lod|apt|pob|sht|dds|tga|iff|flr)\x00',data) for x in [x[:-1]]]

if __name__=='__main__':
    import sys
    t=TreSet(sys.argv[1])
    print(len(t.entries),'resources')
    for name in t.entries:
        if any(s in name for s in sys.argv[2:]):print(name)
