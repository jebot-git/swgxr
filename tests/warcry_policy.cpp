#include "../server/combat/WarcryPolicy.h"
#include <cassert>
#include <limits>
int main(){using namespace corecu::warcry;Vec feet{{0,0,0}},origin{{0,1.7,0}},forward{{0,0,-1}};
 assert(validPose(origin,forward,feet));assert(!validPose({{0,3,0}},forward,feet));assert(!validPose(origin,{{0,0,-2}},feet));assert(!validPose(origin,{{0,1,0}},feet));
 assert(inCone(feet,forward,{{0,0,-24}}));assert(!inCone(feet,forward,{{0,0,-24.01}}));assert(!inCone(feet,forward,{{0,0,5}}));assert(!inCone(feet,forward,{{5,0,0}}));assert(inCone(feet,forward,{{4.9,0,-8.7}}));assert(!inCone(feet,forward,{{5.1,0,-8.6}}));assert(!inCone(feet,forward,{{0,25,-1}}));
 double nan=std::numeric_limits<double>::quiet_NaN();assert(!validPose({{nan,0,0}},forward,feet));assert(!inCone(feet,forward,{{nan,0,0}}));
 assert(duration(false)==6 && duration(true)==8 && delay(false)==2 && delay(true)==3);
}
