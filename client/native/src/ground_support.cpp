#include "ground_support.h"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <algorithm>
#include <cmath>
#include <limits>
using namespace godot;
namespace {
Vector3 point(const Array &a,int index) { return Vector3(a[index*3],a[index*3+1],a[index*3+2]); }
}
void SwgGroundSupport::_bind_methods() {
    ClassDB::bind_method(D_METHOD("configure","regions"),&SwgGroundSupport::configure);
    ClassDB::bind_method(D_METHOD("adopt_region","key","prepared"),&SwgGroundSupport::adopt_region);
    ClassDB::bind_method(D_METHOD("remove_region","key"),&SwgGroundSupport::remove_region);
    ClassDB::bind_method(D_METHOD("sample_support","position","allowed_cell_ids","max_up","max_down","previous"),&SwgGroundSupport::sample_support,DEFVAL(Dictionary()));
    ClassDB::bind_method(D_METHOD("capsule_support","position","radius","allowed_cell_ids","max_up","max_down"),&SwgGroundSupport::capsule_support);
    ClassDB::bind_method(D_METHOD("constrain_motion","position","motion","allowed_cell_ids","radius","height_tolerance"),&SwgGroundSupport::constrain_motion,DEFVAL(0.35));
}
bool SwgGroundSupport::configure(const Array &regions) {
    this->regions.clear();floor_index.clear();
    floors.clear();
    for(int r=0;r<regions.size();r++) {
        const Dictionary region=regions[r];
        const Transform3D transform=region.get("transform",Transform3D());
        const Dictionary definitions=region.get("cells",Dictionary());
        const Array keys=definitions.keys();
        for(int k=0;k<keys.size();k++) {
            const Dictionary definition=definitions[keys[k]];
            const Array vertices=definition.get("floor_vertices",Array());
            if(vertices.size()%3) return false;
            Array triangles=definition.get("floor_triangles",Array());
            if(triangles.is_empty()) {
                const Array indices=definition.get("floor_indices",Array());
                for(int i=0;i+2<indices.size();i+=3) {
                    Dictionary triangle; Array tri;tri.push_back(indices[i]);tri.push_back(indices[i+1]);tri.push_back(indices[i+2]);
                    triangle["id"]=i/3;triangle["indices"]=tri;triangles.push_back(triangle);
                }
            }
            Floor floor;floor.id=keys[k];floor.building=definition.get("building_object_id",0);floor.exterior=definition.get("is_exterior",false);
            const double inf=std::numeric_limits<double>::infinity();floor.minimum=Vector3(inf,inf,inf);floor.maximum=-floor.minimum;
            for(int i=0;i<triangles.size();i++) {
                const Dictionary source=triangles[i];
                if(bool(source.get("fallthrough",false))) continue;
                const Array ids=source.get("indices",Array());
                if(ids.size()!=3) return false;
                for(int j=0;j<3;j++) if(int64_t(ids[j])<0 || int64_t(ids[j])>=vertices.size()/3) return false;
                Triangle t;t.a=transform.xform(point(vertices,ids[0]));t.b=transform.xform(point(vertices,ids[1]));t.c=transform.xform(point(vertices,ids[2]));
                t.normal=(t.b-t.a).cross(t.c-t.a).normalized();
                // Source FLR <=0006 stores inverted normals. Updated imports
                // apply the original post-load correction; old imports retain
                // the version so this compatibility path can do it once.
                const Array normal=source.get("normal",Array());
                if(normal.size()==3) {
                    t.normal=transform.basis.inverse().transposed().xform(Vector3(normal[0],normal[1],normal[2])).normalized();
                    const String version=definition.get("floor_version",String());
                    if(!bool(definition.get("floor_normals_corrected",false))&&!version.is_empty()&&version.to_int()<=6)t.normal=-t.normal;
                } else if(t.normal.y<0)t.normal=-t.normal;
                if(!t.a.is_finite()||!t.b.is_finite()||!t.c.is_finite()||t.normal.y<=0.00001) continue;
                t.id=source.get("id",i);t.neighbors=source.get("neighbors",Array());t.edges=source.get("edge_flags",Array());t.portals=source.get("portal_ids",Array());
                for(const Vector3 &p:{t.a,t.b,t.c}) {floor.minimum=floor.minimum.min(p);floor.maximum=floor.maximum.max(p);}
                floor.triangles.push_back(t);
            }
            if(!floor.triangles.empty()) floors.push_back(std::move(floor));
        }
    }
    rebuild_index();return true;
}
void SwgGroundSupport::rebuild_index() {
    floor_index.clear();
    for(const Floor &floor:floors)floor_index.push_back(&floor);
    for(const auto &entry:regions)for(const Floor &floor:entry.second)floor_index.push_back(&floor);
}
bool SwgGroundSupport::adopt_region(const String &key,const Ref<SwgGroundSupport> &prepared) {
    if(prepared.is_null()||prepared.ptr()==this)return false;
    regions[key]=std::move(prepared->floors);prepared->rebuild_index();rebuild_index();return true;
}
void SwgGroundSupport::remove_region(const String &key) {regions.erase(key);rebuild_index();}
Dictionary SwgGroundSupport::sample_support(const Vector3 &position,const Array &allowed,double max_up,double max_down,const Dictionary &previous) const {
    Dictionary result;result["valid"]=false;
    if(!position.is_finite()||!std::isfinite(max_up)||!std::isfinite(max_down)||max_up<0||max_down<0)return result;
    const Floor *best_floor=nullptr;const Triangle *best=nullptr;double best_height=-std::numeric_limits<double>::infinity();
    const String previous_cell=previous.get("cell_id",String());const int64_t previous_tri=previous.get("tri_id",int64_t(-1));
    for(const Floor *entry:floor_index) {const Floor &floor=*entry;
        if(!allowed.is_empty()&&!allowed.has(floor.id))continue;
        if(position.x<floor.minimum.x-1e-5||position.x>floor.maximum.x+1e-5||position.z<floor.minimum.z-1e-5||position.z>floor.maximum.z+1e-5)continue;
        for(const Triangle &t:floor.triangles) {
            Vector3 u=t.b-t.a,v=t.c-t.a,p=position-t.a;
            double det=u.x*v.z-v.x*u.z;if(std::abs(det)<1e-10)continue;
            double b=(p.x*v.z-v.x*p.z)/det,c=(u.x*p.z-p.x*u.z)/det;
            if(b<-1e-6||c<-1e-6||b+c>1.000001)continue;
            double height=t.a.y+b*u.y+c*v.y;
            if(height>position.y+max_up+1e-5||height<position.y-max_down-1e-5)continue;
            bool retain=previous_cell==floor.id&&previous_tri==t.id;
            if(!best||height>best_height+1e-5||(std::abs(height-best_height)<=1e-5&&retain)) {best=&t;best_floor=&floor;best_height=height;}
        }
    }
    if(best) {
        result["valid"]=true;result["height"]=best_height;result["position"]=Vector3(position.x,best_height,position.z);result["normal"]=best->normal;
        result["cell_id"]=best_floor->id;result["building_object_id"]=best_floor->building;result["is_exterior"]=best_floor->exterior;result["tri_id"]=best->id;
        result["neighbors"]=best->neighbors;result["edge_flags"]=best->edges;result["portal_ids"]=best->portals;result["fallthrough"]=false;
    }
    return result;
}

Dictionary SwgGroundSupport::capsule_support(const Vector3 &position,double radius,const Array &allowed,double max_up,double max_down) const {
    Dictionary result;result["valid"]=false;
    if(!position.is_finite()||!std::isfinite(radius)||radius<=0||!std::isfinite(max_up)||!std::isfinite(max_down))return result;
    double best=-std::numeric_limits<double>::infinity();
    auto accept=[&](double height) {if(height<=position.y+max_up+1e-5&&height>=position.y-max_down-1e-5)best=std::max(best,height);};
    for(const Floor *entry:floor_index) {const Floor &floor=*entry;
        if(!allowed.is_empty()&&!allowed.has(floor.id))continue;
        if(position.x<floor.minimum.x-radius||position.x>floor.maximum.x+radius||position.z<floor.minimum.z-radius||position.z>floor.maximum.z+radius)continue;
        for(const Triangle &t:floor.triangles) {
            // Maximize plane(q) + sqrt(radius² - |q.xz-center.xz|²) - radius
            // over this triangle. The maximum is either its free stationary
            // point or on an edge; testing both retains continuous crest/edge
            // support instead of extending a ramp plane past its boundary.
            const Vector3 q=position-Vector3(t.normal.x,0,t.normal.z)*radius;
            Vector3 u=t.b-t.a,v=t.c-t.a,p=q-t.a;
            double det=u.x*v.z-v.x*u.z;
            if(std::abs(det)>1e-10) {
                double b=(p.x*v.z-v.x*p.z)/det,c=(u.x*p.z-p.x*u.z)/det;
                if(b>=0&&c>=0&&b+c<=1)accept(t.a.y+b*u.y+c*v.y+radius*t.normal.y-radius);
            }
            const Vector3 points[3]={t.a,t.b,t.c};
            for(int e=0;e<3;e++) {
                Vector3 a=points[e],b=points[(e+1)%3],d=b-a,offset=position-a;
                double length=std::sqrt(d.x*d.x+d.z*d.z);if(length<1e-9)continue;
                double along=(offset.x*d.x+offset.z*d.z)/length;
                double perpendicular=std::max(0.0,double(offset.x*offset.x+offset.z*offset.z)-along*along);
                if(perpendicular>radius*radius)continue;
                double remaining=std::sqrt(std::max(0.0,radius*radius-perpendicular));
                double slope=d.y/length;
                double distance=std::clamp(along+remaining*slope/std::sqrt(1+slope*slope),0.0,length);
                double square=radius*radius-perpendicular-(distance-along)*(distance-along);
                if(square>=-1e-9)accept(a.y+distance*slope+std::sqrt(std::max(0.0,square))-radius);
            }
        }
    }
    if(std::isfinite(best)){result["valid"]=true;result["body_height"]=best;}
    return result;
}

Dictionary SwgGroundSupport::constrain_motion(const Vector3 &position,const Vector3 &motion,const Array &allowed,double radius,double tolerance) const {
    Dictionary result;result["motion"]=motion;result["blocked"]=false;
    if(!position.is_finite()||!motion.is_finite()||!std::isfinite(radius)||radius<0||allowed.is_empty())return result;
    Vector3 moved,remaining(motion.x,0,motion.z);
    for(int iteration=0;iteration<3&&remaining.length_squared()>1e-14;iteration++) {
        const Vector3 start=position+moved;double earliest=1.0;Vector3 hit_normal;String cell;int64_t tri=-1,edge=-1;
        for(const Floor *entry:floor_index) {const Floor &floor=*entry;
            if(!allowed.has(floor.id))continue;
            for(const Triangle &t:floor.triangles) {
                if(t.edges.size()!=3)continue;
                // Only constrain this walking support level, not a roof or a
                // different storey whose boundary overlaps the same X/Z.
                const double plane=t.a.y-(t.normal.x*(start.x-t.a.x)+t.normal.z*(start.z-t.a.z))/t.normal.y;
                if(std::abs(plane-start.y)>tolerance+radius)continue;
                const Vector3 points[3]={t.a,t.b,t.c};
                for(int e=0;e<3;e++) {
                    // A source portal overrides the raw edge flag. Crossable
                    // and wall-base transitions are left to the source floor
                    // and authored volume solver; only explicit closed edges
                    // create a lateral walking constraint here.
                    if(int(t.edges[e])!=0||(t.portals.size()==3&&int(t.portals[e])>=0))continue;
                    Vector3 a=points[e],b=points[(e+1)%3],third=points[(e+2)%3];
                    Vector3 tangent=b-a;tangent.y=0;double length=tangent.length();if(length<1e-8)continue;tangent/=length;
                    Vector3 normal(-tangent.z,0,tangent.x);if(normal.dot(third-a)<0)normal=-normal;
                    double approach=normal.dot(remaining);if(approach>=-1e-10)continue;
                    double distance=normal.dot(start-a);if(distance< -1e-5)continue;
                    double time=std::max(0.0,(distance-radius)/-approach);if(time>=earliest)continue;
                    Vector3 contact=start+remaining*time;
                    double along=tangent.dot(contact-a);
                    if(along<0||along>length)continue;
                    earliest=time;hit_normal=normal;cell=floor.id;tri=t.id;edge=e;
                }
            }
        }
        moved+=remaining*earliest;
        if(earliest>=1)break;
        remaining*=1-earliest;
        remaining-=hit_normal*std::min(0.0,double(remaining.dot(hit_normal)));
        result["blocked"]=true;result["cell_id"]=cell;result["tri_id"]=tri;result["edge"]=edge;
    }
    moved.y=motion.y;result["motion"]=moved;return result;
}
