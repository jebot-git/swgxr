#include <vector>
#include <cmath>
#include <stdexcept>
#include <iostream>
struct Vector3 {float x,y,z;Vector3(float a=0,float b=0,float c=0):x(a),y(b),z(c){}float getX()const{return x;}float getY()const{return y;}float getZ()const{return z;}void set(float a,float b,float c){x=a;y=b;z=c;}Vector3 operator-(const Vector3&o)const{return {x-o.x,y-o.y,z-o.z};}float distanceTo(const Vector3&o)const{auto d=*this-o;return std::sqrt(d.x*d.x+d.y*d.y+d.z*d.z);}void normalize(){float n=distanceTo({});x/=n;y/=n;z/=n;}};
struct Ray {Vector3 start,direction;Ray(Vector3 a,Vector3 b):start(a),direction(b){}};struct Triangle {};
struct Appearance {bool solid=false;int queries=0;bool intersects(const Ray&r,float distance,float&,Triangle*&,bool){++queries;if(!solid || std::abs(r.direction.y)<.001)return false;float t=(18-r.start.y)/r.direction.y;return t>=0&&t<=distance;}};
struct Layout {std::vector<Appearance*> cells;int getAppearanceTemplatesSize(){return cells.size();}Appearance*getAppearanceTemplate(int i){return cells.at(i);}};
struct Template {Layout*layout;Layout*getPortalLayout(){return layout;}};
struct ShipObject {Template t;Template*getObjectTemplate(){return &t;}};
struct CreatureObject {Vector3 position;Vector3 getPosition(){return position;}};
#include "jtl_walk_native.inc"
int main(){Appearance oldRoom,newRoom;Layout layout{{nullptr,&oldRoom,&newRoom}};ShipObject ship{{&layout}};CreatureObject c{{0,19,0}};int checks=0;auto check=[&](bool v){++checks;if(!v)throw std::runtime_error("walk geometry check failed");};
check(NativeJtl::walkClear(&c,&ship,{0,17,0}));check(oldRoom.queries==1&&newRoom.queries==1);
oldRoom.solid=true;check(!NativeJtl::walkClear(&c,&ship,{0,17,0}));oldRoom.solid=false;newRoom.solid=true;check(!NativeJtl::walkClear(&c,&ship,{0,17,0}));
check(NativeJtl::walkClear(&c,&ship,c.position));ship.t.layout=nullptr;check(!NativeJtl::walkClear(&c,&ship,{0,17,0}));std::cout<<checks<<" production doorway/wall ray checks passed\n";}
