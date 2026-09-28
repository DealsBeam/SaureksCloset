"""Native rig layout and actual skin bindings, independent of the exporter."""
from collections import Counter
import math
from pathlib import Path
import struct as S
import sys

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from build_bag_deformation import volume_rig, MARKER


def audit(path):
    data=path.read_bytes()
    def array(offset,stride):
        count,start=S.unpack_from('<II',data,offset)
        assert count>0 and start>=0x144 and start+count*stride<=len(data)
        return count,start
    count,start=array(8,1);assert data[start:start+count]==MARKER
    count,start=array(0x1c,68);assert count==1 and S.unpack_from('<H',data,start)[0]==0
    count,start=array(0x34,108);assert count==61
    nodes=[]
    for i in range(1,count):
        assert S.unpack_from('<Ih',data,start+108*i+4)==(0x200,0)
        assert data[start+108*i+12:start+108*i+96]==S.pack('<Hh6I',0,-1,0,0,0,0,0,0)*3
        nodes.append(S.unpack_from('<3f',data,start+108*i+96))
    n,start=array(0x44,48);vertices=[];weights=[];bones=[]
    for i in range(n):
        fields=S.unpack_from('<3f8B3f4f',data,start+48*i)
        vertices.append(fields[:3]);weights.append(fields[3:7]);bones.append(fields[7:11])
        assert sum(weights[-1])==255 and all(1<=b<=60 for b in bones[-1])
        reconstructed=[sum(nodes[b-1][axis]*w/255 for b,w in zip(bones[-1],weights[-1])) for axis in range(3)]
        assert max(abs(a-b) for a,b in zip(reconstructed,vertices[-1]))<.006
    low=[min(p[i] for p in nodes) for i in range(3)];high=[max(p[i] for p in nodes) for i in range(3)]
    assert len({p[0] for p in nodes})==3 and len({p[1] for p in nodes})==4 and len({p[2] for p in nodes})==5
    # UV seams/overlapping material pieces must share the very same field.
    seen={}
    for p,w,b in zip(vertices,weights,bones):
        if p in seen:assert seen[p]==(w,b)
        seen[p]=(w,b)
    count,view=array(0x4c,44);assert count==1
    count,lookup_at=array(view,2);lookup=S.unpack_from('<'+'H'*count,data,lookup_at)
    _,props=array(view+16,4)
    nt,index_at=array(view+8,2);indices=S.unpack_from('<'+'H'*nt,data,index_at)
    count,palettes_at=array(0x8c,2);palettes=S.unpack_from('<'+'H'*count,data,palettes_at)
    sections,section_at=array(view+24,32)
    assert sections<=24,'Local rig draw budget exceeded'
    drawn=[]
    for i in range(sections):
        _,_,first,nv,tri,ni,nb,bone_start,influences,_=S.unpack_from('<10H',data,section_at+32*i)
        assert nb<=21 and 1<=influences<=4 and first+nv<=len(lookup)
        for v in range(first,first+nv):
            vertex=lookup[v];assert vertex<n
            for j in range(4):
                if weights[vertex][j]:assert palettes[bone_start+data[props+4*v+j]]==bones[vertex][j]
        assert all(first<=v<first+nv for v in indices[tri:tri+ni])
        drawn.extend(lookup[v] for v in indices[tri:tri+ni])
    assert len(drawn)==nt
    assert array(view+32,24)[0]==sections
    return sections,Counter(tuple(drawn[i:i+3]) for i in range(0,len(drawn),3))


if __name__=='__main__':
    # Shared field interpolates continuous geometry without separate flap tracks.
    nodes,w,b=volume_rig([(0,0,0),(1,1,1),(.3,.7,.4),(.3,.7,.4)])
    assert w[2]==w[3] and b[2]==b[3]
    paths=list((ROOT/'addon/SaureksCloset/Models').glob('*.m2'))
    for path in paths:audit(path)
    print('PASS: %d locally skinned bags; pinned-capable volume grids, shared seam bindings, 4 weights, bounded palettes, Stand-only assets'%len(paths))
