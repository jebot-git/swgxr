"""Exercise the actual native octree bounds methods across all eight octants."""
import subprocess
import tempfile
import unittest
from pathlib import Path
from tests.test_carbineer_native import method
ROOT=Path(__file__).resolve().parents[1]
class SpaceOctree(unittest.TestCase):
 def test_translated_octants_keep_nearby_objects_visible(self):
  source=(ROOT/'vendor/Core3/MMOCoreORB/src/server/zone/TreeNode.cpp').read_text()
  bounds=method(source,'void TreeNode::setBoundingSphere()').replace('TreeNode::','')
  check=method(source,'bool TreeNode::testInRange(float x, float y, float z, float range)').replace('TreeNode::','')
  header=(ROOT/'vendor/Core3/MMOCoreORB/src/server/zone/TreeNode.h').read_text()
  distance=method(header,'\tinline float squaredDistanceToCenter(')
  code='''#include <cmath>
#include <cassert>
struct TreeNode {
 enum { OCTREE_NODE=1 }; int nodeType=OCTREE_NODE;
 float minX,minY,minZ,maxX,maxY,maxZ,centerX,centerY,centerZ,radius;
'''+bounds+check+distance+'''
};
int main(){
 for(int x=-8192;x<8192;x+=1024)for(int y=-8192;y<8192;y+=1024)for(int z=-8192;z<8192;z+=1024){
  TreeNode n; n.minX=x;n.minY=y;n.minZ=z;n.maxX=x+1024;n.maxY=y+1024;n.maxZ=z+1024;n.setBoundingSphere();
  assert(n.testInRange(x+512,y+512,z+512,1));
  assert(n.testInRange(x,y,z,1));
  assert(n.testInRange(x+1023,y+1023,z+1023,1));
  assert(!n.testInRange(x+8192,y+8192,z+8192,100));
 }
}
'''
  with tempfile.TemporaryDirectory() as tmp:
   p=Path(tmp);(p/'check.cpp').write_text(code)
   subprocess.run(['c++','-std=c++17',str(p/'check.cpp'),'-o',str(p/'check')],check=True,capture_output=True)
   subprocess.run([str(p/'check')],check=True,capture_output=True)
if __name__=='__main__':unittest.main()
