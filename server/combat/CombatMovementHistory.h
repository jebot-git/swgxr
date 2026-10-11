#pragma once
#include <array>
#include <deque>
#include <cmath>
#include <cstdint>
namespace corecu { namespace history {
using Vec=std::array<double,3>;
struct Sample {double at;Vec point;uint64_t zone,cell;bool lineClear;};
struct History {
 std::deque<Sample> samples;
 void observe(double at,Vec point,uint64_t zone,uint64_t cell,bool lineClear=true){
  if(!samples.empty() && (samples.back().zone!=zone || samples.back().cell!=cell || distance(samples.back().point,point)>32))samples.clear();
  if(!samples.empty()&&at<samples.back().at)return;
  samples.push_back({at,point,zone,cell,lineClear});while(samples.size()>64||(!samples.empty()&&at-samples.front().at>2.5))samples.pop_front();
 }
 static double distance(Vec a,Vec b){double sum=0;for(int i=0;i<3;++i){double d=a[i]-b[i];sum+=d*d;}return std::sqrt(sum);}
 const Sample* nearest(double at,double now,uint64_t zone,uint64_t cell,double tolerance=.35) const {
  if(!std::isfinite(at)||at>now+.05||now-at>2.)return nullptr;
  const Sample* found=nullptr;double delta=tolerance;
  for(const auto& p:samples)if(p.zone==zone&&p.cell==cell&&std::abs(p.at-at)<=delta){found=&p;delta=std::abs(p.at-at);}
  return found;
 }
 bool contact(Vec point,double at,double now,uint64_t zone,uint64_t cell) const {
  auto p=nearest(at,now,zone,cell,.12);
  // Same native floor at contact time; allow uneven ground and animation height.
  return p&&p->lineClear&&distance(point,p->point)<=4.&&std::abs(point[1]-p->point[1])<=1.25;
 }
 bool matches(Vec point,double at,double now,uint64_t zone,uint64_t cell,double radius=4.) const {
  auto p=nearest(at,now,zone,cell);return p&&distance(point,p->point)<=radius;
 }
};
}}
