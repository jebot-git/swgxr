"""Exercise the actual native codec used on both sides of the SOE transport."""
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

class SnapshotCodec(unittest.TestCase):
    def test_roundtrip_and_bounded_decode(self):
        source = r'''
#include "server/transport/SnapshotCodec.h"
#include <cassert>
#include <iostream>
using namespace swgxr::snapshot_codec;
int main() {
    std::string small = "{\"session_live\":true}";
    assert(encode(small) == small && decode(small) == small);
    std::string large;
    for (int i=0; i<1000; ++i) large += "{\"actor\":\"original_npc\",\"position\":[123.5,4,-999],\"ham\":[100,100,100]}";
    auto packed = encode(large);
    assert(packed.size() < large.size()/10 && decode(packed) == large);
    std::string binary;
    for (int i=0; i<16384; ++i) binary += char(i%256);
    assert(decode(encode(binary)) == binary);
    for (auto bad : {"z1:", "z1:0:00", "z1:4194305:00", "z1:-1:00", "z1:100:xx", "z1:100:0", "z1:100:0000"}) {
        bool rejected=false; try { decode(bad); } catch(const std::runtime_error&) { rejected=true; }
        assert(rejected);
    }
    auto wrong_length = packed; wrong_length[3] = '1';
    bool rejected=false; try { decode(wrong_length); } catch(const std::runtime_error&) { rejected=true; }
    assert(rejected);
    rejected=false; try { decode(std::string(max_bytes+1, 'a')); } catch(const std::runtime_error&) { rejected=true; }
    assert(rejected);
    std::cout << "Native snapshot codec roundtrip, legacy JSON, binary, malformed and allocation bounds passed\n";
}
'''
        with tempfile.TemporaryDirectory() as folder:
            folder = Path(folder)
            (folder/'test.cpp').write_text(source)
            subprocess.run(['c++','-std=c++14','-I'+str(ROOT),str(folder/'test.cpp'),'-lz','-o',str(folder/'test')],check=True,timeout=30)
            subprocess.run([str(folder/'test')],check=True,timeout=10)
        self.assertEqual((ROOT/'server/transport/SnapshotCodec.h').read_bytes(), (ROOT/'vendor/Core3/MMOCoreORB/src/server/zone/objects/creature/commands/SnapshotCodec.h').read_bytes())

if __name__ == '__main__': unittest.main()
