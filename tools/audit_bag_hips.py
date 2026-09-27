"""Verify the bag hip attachment fixture against installed build-5875 models.

Uses the same StormLib reader and WOW_DATA setting as the existing contact-fit
and weapon attachment audits. Only numeric skeleton metadata is retained.
"""
import ctypes as C
from pathlib import Path
import struct
import sys
import read_client_data as client

root=Path(__file__).resolve().parents[1]
rows=[]
try:
    for name in ["patch-2.MPQ","patch.MPQ","model.MPQ"]:
        handle=C.c_void_p()
        assert client.lib.SFileOpenArchive(str(client.game/name).encode(),0,0x100,C.byref(handle)),name
        client.archives.append(handle)
    for race,name in enumerate(["Human","Orc","Dwarf","NightElf","Scourge","Tauren","Gnome","Troll"],1):
        for sex,sexname in enumerate(["Male","Female"]):
            filename=f"Character\\{name}\\{sexname}\\{name}{sexname}.m2"
            data=client.read(filename)
            assert data and data[:8]==b"MD20\x00\x01\x00\x00",filename
            count,offset=struct.unpack_from("<II",data,0x104)
            lookup_count,lookup=struct.unpack_from("<II",data,0x10C)
            bone_count,bones=struct.unpack_from("<II",data,0x34)
            assert 33<lookup_count<=512 and 0<count<=512 and 0<bone_count<=2048
            for point in [32,33]:
                index=struct.unpack_from("<H",data,lookup+2*point)[0]
                assert index<count
                actual,bone,unused,x,y,z=struct.unpack_from("<IHH3f",data,offset+48*index)
                assert actual==point and bone<bone_count
                parent=struct.unpack_from("<h",data,bones+108*bone+8)[0]
                assert 0<=parent<bone_count
                rows.append((race,sex,point,index,bone,parent,x,y,z))
finally:
    for handle in client.archives:client.lib.SFileCloseArchive(handle)
fixture="// Extracted from all 16 installed build-5875 character models, attachment32/33.\n// Native parent-bone orientation is used; fixture retains metadata only.\nstruct BagHipFixture {unsigned race,sex,point,index,bone,parent;std::array<float,3> position;};\nstatic const BagHipFixture bagHipFixtures[]={\n"
for row in rows:
    fixture+="{%d,%d,%d,%d,%d,%d,{{%.9ff,%.9ff,%.9ff}}},\n"%row
fixture+="};\n"
path=root/"tests/bag_hip_fixtures.h"
if "--write" in sys.argv:path.write_text(fixture)
else:assert path.read_text()==fixture,"Installed bag hip attachment metadata differs from the audited fixture."
print("PASS: bag hip points, bones, parent bones and coordinates verified for all 16 installed body models.")
