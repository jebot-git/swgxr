#include "combat_collision.h"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <algorithm>
#include <cmath>
#include <functional>
namespace godot {
namespace {
bool box_interval(const AABB &box,const Vector3 &a,const Vector3 &d,double &lo,double &hi,bool planar=false) {
    for(int axis=0;axis<3;axis++) {
        if(planar && axis==1) continue;
        const double low=box.position[axis],high=low+box.size[axis];
        if(std::abs(d[axis])<1e-10) {if(a[axis]<low-1e-5||a[axis]>high+1e-5)return false;continue;}
        double x=(low-a[axis])/d[axis],y=(high-a[axis])/d[axis];
        if(x>y)std::swap(x,y);lo=std::max(lo,x);hi=std::min(hi,y);if(lo>hi+1e-6)return false;
    }return true;
}
bool triangle_hit(const Vector3 &a,const Vector3 &d,const Vector3 &v0,const Vector3 &v1,const Vector3 &v2,double &t) {
    const Vector3 e1=v1-v0,e2=v2-v0,p=d.cross(e2);const double det=e1.dot(p);
    if(std::abs(det)<1e-10)return false;
    const Vector3 q0=a-v0;const double u=q0.dot(p)/det;if(u<-1e-6||u>1.000001)return false;
    const Vector3 q=q0.cross(e1);const double v=d.dot(q)/det;if(v<-1e-6||u+v>1.000001)return false;
    t=e2.dot(q)/det;return t>=-1e-6&&t<=1.000001;
}
bool polygon_hit(const std::vector<Vector3>&p,const Vector3&a,const Vector3&d,double&t) {
    for(size_t i=1;i+1<p.size();i++)if(triangle_hit(a,d,p[0],p[i],p[i+1],t))return true;return false;
}
}
void SwgCombatCollision::_bind_methods() {
    ClassDB::bind_method(D_METHOD("configure","regions"),&SwgCombatCollision::configure);
    ClassDB::bind_method(D_METHOD("set_geometry","key","surfaces","coverage","coverage_layer"),&SwgCombatCollision::set_geometry,DEFVAL(1));
    ClassDB::bind_method(D_METHOD("adopt_geometry","key","prepared","source_key"),&SwgCombatCollision::adopt_geometry);
    ClassDB::bind_method(D_METHOD("remove_geometry","key"),&SwgCombatCollision::remove_geometry);
    ClassDB::bind_method(D_METHOD("set_require_terrain","value"),&SwgCombatCollision::set_require_terrain);
    ClassDB::bind_method(D_METHOD("trace_segment","from","to","cell_id","mask"),&SwgCombatCollision::trace_segment,DEFVAL(String()),DEFVAL(7));
    ClassDB::bind_method(D_METHOD("trace_segments","segments"),&SwgCombatCollision::trace_segments);
    ClassDB::bind_method(D_METHOD("statistics"),&SwgCombatCollision::statistics);
}
void SwgCombatCollision::configure(const Array &regions) {
    cells.clear();
    for(int r=0;r<regions.size();r++) {
        const Dictionary region=regions[r],defs=region.get("cells",Dictionary());const Transform3D transform=region.get("transform",Transform3D());const Array keys=defs.keys();
        for(int i=0;i<keys.size();i++) {
            const Dictionary src=defs[keys[i]];Cell cell;cell.exterior=src.get("is_exterior",false);const Array portals=src.get("portals",Array());
            for(int j=0;j<portals.size();j++) {
                const Dictionary p=portals[j];if(!bool(p.get("passable",false))||bool(p.get("source_disabled",false)))continue;
                Portal portal;portal.target=p.get("leads_to",String());const Array verts=p.get("vertices",Array());
                for(int v=0;v+2<verts.size();v+=3)portal.points.push_back(transform.xform(Vector3(verts[v],verts[v+1],verts[v+2])));
                if(portal.points.size()>=3)cell.portals.push_back(std::move(portal));
            }cells[String(keys[i])]=std::move(cell);
        }
    }
}
int SwgCombatCollision::build(Group &g,int start,int count) {
    const int index=g.tree.size();g.tree.push_back({});AABB bounds=g.triangles[start].bounds;
    for(int i=start+1;i<start+count;i++)bounds=bounds.merge(g.triangles[i].bounds);
    g.tree[index].bounds=bounds;g.tree[index].start=start;g.tree[index].count=count;
    if(count>8) {
        const int axis=bounds.get_longest_axis_index();const int mid=start+count/2;
        std::nth_element(g.triangles.begin()+start,g.triangles.begin()+mid,g.triangles.begin()+start+count,[axis](const Triangle&a,const Triangle&b){return a.bounds.get_center()[axis]<b.bounds.get_center()[axis];});
        const int left=build(g,start,mid-start),right=build(g,mid,start+count-mid);
        g.tree[index].left=left;g.tree[index].right=right;g.tree[index].count=0;
    }return index;
}
void SwgCombatCollision::set_geometry(const String&key,const Array&surfaces,const AABB&coverage,int coverage_layer) {
    Group g;g.coverage=coverage;g.coverage_layer=coverage_layer;
    for(int i=0;i<surfaces.size();i++) {
        const Dictionary s=surfaces[i];if(bool(s.get("unsupported",false)))g.valid=false;const PackedVector3Array points=s.get("faces",PackedVector3Array());const Transform3D transform=s.get("transform",Transform3D());const String cell=s.get("cell_id",String());const int layer=s.get("layer",1);
        for(int j=0;j+2<points.size();j+=3) {
            Triangle t{transform.xform(points[j]),transform.xform(points[j+1]),transform.xform(points[j+2]),cell,layer,{}};
            if(!t.a.is_finite()||!t.b.is_finite()||!t.c.is_finite()||(t.b-t.a).cross(t.c-t.a).length_squared()<1e-14)continue;
            t.bounds=AABB(t.a,Vector3()).expand(t.b).expand(t.c).grow(0.00001);g.triangles.push_back(std::move(t));
        }
    }
    if(!g.triangles.empty())build(g,0,g.triangles.size());groups[key]=std::move(g);
}
bool SwgCombatCollision::adopt_geometry(const String&key,const Ref<SwgCombatCollision>&prepared,const String&source_key) {
    if(prepared.is_null()||prepared.ptr()==this)return false;
    auto item=prepared->groups.find(source_key);if(item==prepared->groups.end())return false;
    groups[key]=std::move(item->second);prepared->groups.erase(item);return true;
}
void SwgCombatCollision::remove_geometry(const String&key){groups.erase(key);}
void SwgCombatCollision::set_require_terrain(bool value){require_terrain=value;}
bool SwgCombatCollision::covered(const Vector3&a,const Vector3&b,int layer)const {
    std::vector<std::pair<double,double>> intervals;
    for(const auto &entry:groups)if(entry.second.coverage_layer&layer){double lo=0,hi=1;if(box_interval(entry.second.coverage,a,b-a,lo,hi,true))intervals.push_back({lo,hi});}
    std::sort(intervals.begin(),intervals.end());double end=0;
    for(const auto &i:intervals){if(i.first>end+1e-5)break;end=std::max(end,i.second);if(end>=1-1e-6)return true;}return false;
}
Dictionary SwgCombatCollision::trace_segment(const Vector3&from,const Vector3&to,const String&cell_id,int mask)const {
    Dictionary result;result["hit"]=false;result["complete"]=false;result["position"]=to;result["normal"]=Vector3();result["fraction"]=1.0;result["cell_id"]=cell_id;result["end_cell_id"]=cell_id;result["source_layer"]=0;
    int tested=0,crossings=0;bool complete=from.is_finite()&&to.is_finite();String state=cell_id;
    if(!state.is_empty()&&!cells.count(state))complete=false;
    if(!complete){result["reason"]="invalid_coordinates_or_unknown_cell";return result;}
    if(!state.is_empty()&&cells.at(state).exterior)state=String();
    const Vector3 direction=to-from;double consumed=0;
    for(int step=0;step<64;step++) {
        double next=1;String target;bool transition=false;
        for(const auto &entry:cells) {
            if(state.is_empty()?!entry.second.exterior:entry.first!=state)continue;
            for(const Portal&p:entry.second.portals){double t;if(polygon_hit(p.points,from,direction,t)&&t>consumed+1e-6&&t<=next&&t<=1){next=t;target=p.target;transition=true;}}
        }
        double hit_t=next+1e-6;const Triangle *hit=nullptr;
        for(const auto &entry:groups) {
            const Group &g=entry.second;double invalid_lo=consumed,invalid_hi=next;if(!g.valid&&box_interval(g.coverage,from,direction,invalid_lo,invalid_hi,true))complete=false;if(g.tree.empty())continue;
            std::vector<int> stack{0};
            while(!stack.empty()) {
                const Branch &node=g.tree[stack.back()];stack.pop_back();double lo=consumed-1e-6,hi=hit_t;
                if(!box_interval(node.bounds,from,direction,lo,hi))continue;
                if(node.count==0){stack.push_back(node.left);stack.push_back(node.right);continue;}
                for(int i=node.start;i<node.start+node.count;i++) {
                    const Triangle&t=g.triangles[i];if(!(t.layer&mask))continue;
                    if((t.layer&2)&&!state.is_empty())continue;
                    if(!t.cell.is_empty()) {
                        const auto c=cells.find(t.cell);const bool ext=c!=cells.end()&&c->second.exterior;
                        if(state.is_empty()?!ext:t.cell!=state)continue;
                    }
                    tested++;double value;if(triangle_hit(from,direction,t.a,t.b,t.c,value)&&value>=consumed-1e-6&&value<hit_t&&value>1e-6){hit_t=value;hit=&t;}
                }
            }
        }
        const Vector3 endpoint=from+direction*(hit?hit_t:next);
        if(state.is_empty())complete=complete&&(!(mask&5)||covered(from+direction*consumed,endpoint,1))&&(!require_terrain||!(mask&2)||covered(from+direction*consumed,endpoint,2));
        if(hit){Vector3 normal=(hit->b-hit->a).cross(hit->c-hit->a).normalized();if(normal.dot(direction)>0)normal=-normal;result["hit"]=true;result["position"]=endpoint;result["normal"]=normal;result["fraction"]=hit_t;result["source_layer"]=hit->layer;result["cell_id"]=hit->cell;break;}
        if(!transition)break;
        if(!cells.count(target)){complete=false;result["reason"]="unloaded_portal_destination";break;}
        state=cells.at(target).exterior?String():target;consumed=next;crossings++;
        if(next>=1)break;
        if(step==63){complete=false;result["reason"]="portal_traversal_limit";}
    }
    result["complete"]=complete;result["end_cell_id"]=state;result["triangles_tested"]=tested;result["portal_crossings"]=crossings;
    if(!complete&&!result.has("reason"))result["reason"]="unloaded_world_or_terrain_coverage";
    return result;
}
Array SwgCombatCollision::trace_segments(const Array&segments)const {
    Array results;results.resize(segments.size());for(int i=0;i<segments.size();i++){const Dictionary s=segments[i];results[i]=trace_segment(s.get("from",Vector3()),s.get("to",Vector3()),s.get("cell_id",String()),s.get("mask",7));}return results;
}
Dictionary SwgCombatCollision::statistics()const{Dictionary d;int triangles=0,nodes=0;for(const auto&g:groups){triangles+=g.second.triangles.size();nodes+=g.second.tree.size();}d["triangles"]=triangles;d["bvh_nodes"]=nodes;d["geometry_groups"]=int(groups.size());d["cells"]=int(cells.size());d["require_terrain"]=require_terrain;return d;}
}
