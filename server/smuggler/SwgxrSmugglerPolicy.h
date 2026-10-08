#ifndef SWGXR_SMUGGLER_POLICY_H
#define SWGXR_SMUGGLER_POLICY_H
#include <algorithm>
// CU effect types; timing/strength are explicit prototype tuning pending NGE provenance.
struct SwgxrSmugglerPolicy {
 static constexpr int snarePercent=25, snareSeconds=20, concussionSeconds=40;
 static constexpr double concussionDamage=.25;
 static double deficit(int current,int maximum){return 1.0-std::max(0.0,std::min(1.0,double(current)/std::max(1,maximum)));}
 static double lastDitch(int h,int mh,int a,int ma,int m,int mm){return 2.0+deficit(h,mh)+deficit(a,ma)+deficit(m,mm);}
};
#endif
