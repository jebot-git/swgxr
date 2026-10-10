"""Bounded ISO9660 reader for the TTE installer cabinets; never runs installers."""
from pathlib import Path
import hashlib
import re
import struct

SECTOR=2048
CAB=re.compile(r'data[1-9][0-9]*\.(cab|hdr)$',re.I)

def extract_cabinets(image, destination):
    image=Path(image);destination=Path(destination);destination.mkdir(parents=True,exist_ok=True)
    size=image.stat().st_size
    with image.open('rb') as stream:
        def read(offset,count):
            if offset<0 or count<0 or offset+count>size:raise ValueError('ISO extent outside image')
            stream.seek(offset);data=stream.read(count)
            if len(data)!=count:raise ValueError('Truncated ISO')
            return data
        pvd=read(16*SECTOR,SECTOR)
        if pvd[:7]!=b'\x01CD001\x01' or struct.unpack_from('<H',pvd,128)[0]!=SECTOR:raise ValueError('Expected a 2048-byte ISO9660 installation disc')
        def extent(record):return struct.unpack_from('<I',record,2)[0]*SECTOR,struct.unpack_from('<I',record,10)[0]
        pending=[extent(pvd[156:])];visited=set();found=[]
        while pending:
            offset,length=pending.pop()
            if (offset,length) in visited:continue
            visited.add((offset,length))
            if len(visited)>256 or length>16*1024**2:raise ValueError('ISO directory exceeds bounds')
            data=read(offset,length);cursor=0
            while cursor<len(data):
                n=data[cursor]
                if n==0:cursor=((cursor//SECTOR)+1)*SECTOR;continue
                record=data[cursor:cursor+n];cursor+=n
                if n<34 or len(record)!=n:raise ValueError('Truncated ISO directory record')
                name=record[33:33+record[32]]
                if name in (b'\0',b'\1'):continue
                where,count=extent(record)
                if record[25]&2:pending.append((where,count));continue
                filename=name.decode('ascii').split(';')[0].lower()
                if not CAB.fullmatch(filename):continue
                if record[25]&0x80:raise ValueError('Multi-extent installer cabinet unsupported')
                target=destination/filename;temporary=target.with_suffix(target.suffix+'.partial')
                digest=hashlib.sha256()
                try:
                    with temporary.open('wb') as output:
                        for chunk in range(0,count,4*1024**2):
                            block=read(where+chunk,min(4*1024**2,count-chunk));digest.update(block);output.write(block)
                    if target.exists():
                        with target.open('rb') as old:previous=hashlib.file_digest(old,'sha256').hexdigest()
                        if previous!=digest.hexdigest():raise ValueError('Conflicting cabinet across discs: '+filename)
                    temporary.replace(target)
                finally:temporary.unlink(missing_ok=True)
                found.append(dict(name=filename,bytes=count,sha256=digest.hexdigest()))
        if not found:raise ValueError('No Total Experience installer cabinets in '+image.name)
        return found
