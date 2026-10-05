#include "collision_builder.h"
#include <godot_cpp/classes/box_shape3d.hpp>
#include <godot_cpp/classes/sphere_shape3d.hpp>
#include <godot_cpp/classes/cylinder_shape3d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <vector>
#include <cmath>
using namespace godot;
namespace {
Vector3 vec(const Array &a) {return a.size()==3?Vector3(a[0],a[1],a[2]):Vector3();}
Ref<ConcavePolygonShape3D> mesh_shape(const Array &vertices,const Array &indices) {
    Ref<ConcavePolygonShape3D> shape;if(vertices.size()%3||indices.size()%3||indices.is_empty())return shape;
    PackedVector3Array faces;faces.resize(indices.size());
    for(int i=0;i<indices.size();i++) {int64_t j=indices[i];if(j<0||j>=vertices.size()/3)return Ref<ConcavePolygonShape3D>();faces[i]=Vector3(vertices[j*3],vertices[j*3+1],vertices[j*3+2]);}
    shape.instantiate();shape->set_faces(faces);shape->set_backface_collision_enabled(true);return shape;
}
void append(const Dictionary &def,const Transform3D &parent,Array &out,int depth) {
    if(depth>32)return;
    const String type=def.get("type",String());Transform3D transform=parent;
    if(type=="transform") {
        const Array matrix=def.get("matrix",Array());if(matrix.size()!=12)return;
        Basis basis(Vector3(matrix[0],matrix[4],matrix[8]),Vector3(matrix[1],matrix[5],matrix[9]),Vector3(matrix[2],matrix[6],matrix[10]));
        append(def.get("child",Dictionary()),parent*Transform3D(basis,Vector3(matrix[3],matrix[7],matrix[11])),out,depth+1);return;
    }
    if(type=="component"||type=="composite"||type=="detail") {
        const Array children=def.get("children",Array());const int first=(type=="detail"&&children.size()>1)?1:0;
        for(int i=first;i<children.size();i++)append(children[i],parent,out,depth+1);return;
    }
    Ref<Shape3D> shape;
    if(type=="box") {
        Vector3 lo=vec(def.get("min",Array())),hi=vec(def.get("max",Array()));Vector3 size=hi-lo;if(size.x<=0||size.y<=0||size.z<=0)return;
        Ref<BoxShape3D> box;box.instantiate();box->set_size(size);shape=box;transform.origin=parent.xform((lo+hi)*0.5);
    } else if(type=="sphere") {
        double radius=def.get("radius",0.0);if(radius<=0)return;Ref<SphereShape3D> sphere;sphere.instantiate();sphere->set_radius(radius);shape=sphere;transform.origin=parent.xform(vec(def.get("center",Array())));
    } else if(type=="cylinder") {
        double radius=def.get("radius",0.0),height=def.get("height",0.0);if(radius<=0||height<=0)return;Ref<CylinderShape3D> cylinder;cylinder.instantiate();cylinder->set_radius(radius);cylinder->set_height(height);shape=cylinder;transform.origin=parent.xform(vec(def.get("base",Array()))+Vector3(0,height*0.5,0));
    } else if(type=="mesh") shape=mesh_shape(def.get("vertices",Array()),def.get("indices",Array()));
    if(shape.is_valid()) {Dictionary item;item["shape"]=shape;item["transform"]=transform;out.push_back(item);}
}
}
void SwgCollisionBuilder::_bind_methods() {
    ClassDB::bind_method(D_METHOD("build_extent","definition"),&SwgCollisionBuilder::build_extent);
    ClassDB::bind_method(D_METHOD("build_cell_extent","definition","portals"),&SwgCollisionBuilder::build_cell_extent);
    ClassDB::bind_method(D_METHOD("build_floor","cell"),&SwgCollisionBuilder::build_floor);
}
Array SwgCollisionBuilder::build_extent(const Dictionary &definition) const {
    Array result;append(definition,Transform3D(),result,0);return result;
}
Ref<ConcavePolygonShape3D> SwgCollisionBuilder::build_floor(const Dictionary &cell) const {
    const Array vertices=cell.get("floor_vertices",Array());const Array triangles=cell.get("floor_triangles",Array());
    Array indices=cell.get("floor_indices",Array());
    if(!triangles.is_empty()) {indices.clear();for(int i=0;i<triangles.size();i++){const Dictionary triangle=triangles[i];if(bool(triangle.get("fallthrough",false)))continue;Array ids=triangle.get("indices",Array());if(ids.size()==3)for(int j=0;j<3;j++)indices.push_back(ids[j]);}}
    return mesh_shape(vertices,indices);
}

// Godot does not perform the source client's portal-before-cell-extent query.
// Subtract only a finite authored doorway aperture from near-coplanar CMSH
// closure faces. Floors, lintels, side jambs and unrelated shell faces remain.
Array SwgCollisionBuilder::build_cell_extent(const Dictionary &definition,const Array &portals) const {
    Array result=build_extent(definition);
    using Polygon=std::vector<Vector3>;
    auto split=[](const Polygon &poly,const Vector3 &normal,double offset,bool inside) {
        Polygon out;if(poly.empty())return out;
        for(size_t i=0;i<poly.size();i++) {
            const Vector3 a=poly[i],b=poly[(i+1)%poly.size()];
            const double da=normal.dot(a)-offset,db=normal.dot(b)-offset;
            const bool ia=inside?da>=0:da<=0,ib=inside?db>=0:db<=0;
            if(ia)out.push_back(a);
            if(ia!=ib&&std::abs(da-db)>1e-12)out.push_back(a+(b-a)*(da/(da-db)));
        }
        return out;
    };
    for(int shape_index=0;shape_index<result.size();shape_index++) {
        Dictionary item=result[shape_index];Ref<ConcavePolygonShape3D> shape=item["shape"];
        if(shape.is_null())continue;
        const Transform3D transform=item["transform"];
        PackedVector3Array source=shape->get_faces();std::vector<Polygon> pieces;
        for(int t=0;t+2<source.size();t+=3)pieces.push_back({transform.xform(source[t]),transform.xform(source[t+1]),transform.xform(source[t+2])});
        for(int portal_index=0;portal_index<portals.size();portal_index++) {
            const Dictionary portal=portals[portal_index];if(!bool(portal.get("passable",false))||bool(portal.get("source_disabled",false)))continue;
            const Array vertices=portal.get("vertices",Array());if(vertices.size()<9||vertices.size()%3)continue;
            Polygon aperture;Vector3 center;
            for(int i=0;i<vertices.size();i+=3){Vector3 v(vertices[i],vertices[i+1],vertices[i+2]);aperture.push_back(v);center+=v;}
            center/=aperture.size();Vector3 normal=(aperture[1]-aperture[0]).cross(aperture[2]-aperture[0]).normalized();
            if(normal.length_squared()<0.99)continue;
            std::vector<std::pair<Vector3,double>> sides;
            const double offset=normal.dot(aperture[0]);
            double inradius=1e20;
            for(size_t i=0;i<aperture.size();i++) {
                Vector3 n=(aperture[(i+1)%aperture.size()]-aperture[i]).cross(normal).normalized();
                if(n.dot(center-aperture[i])<0)n=-n;
                sides.push_back({n,n.dot(aperture[i])});
                inradius=std::min(inradius,double(n.dot(center-aperture[i])));
            }
            // POB portals and coarse exterior CMSH closure planes need not be
            // coplanar (the theatre shell is 84cm in front of its open portal).
            // Find parallel closure sheets covering the portal center within a
            // finite source-aperture-scaled neighborhood (some shells are layered).
            // Interior cells keep the narrow tolerance: their real walls must
            // never be perforated simply because a doorway faces them.
            double behind=0.1,ahead=0.1;
            std::vector<double> selected;
            if(bool(portal.get("exterior_shell",false))) {
                const double limit=std::max(0.1,std::min(1.5,inradius*0.5));
                std::vector<double> candidates;
                for(const Polygon &piece:pieces) {
                    if(piece.size()<3)continue;
                    const Vector3 fn=(piece[1]-piece[0]).cross(piece[2]-piece[0]).normalized();
                    const double alignment=fn.dot(normal);
                    if(std::abs(alignment)<0.95)continue;
                    const double distance=fn.dot(piece[0]-center)/alignment;
                    if(std::abs(distance)>limit)continue;
                    const Vector3 hit=center+normal*distance;bool covered=true;
                    for(size_t edge=0;edge<piece.size();edge++) {
                        if((piece[(edge+1)%piece.size()]-piece[edge]).cross(hit-piece[edge]).dot(fn)<-1e-5){covered=false;break;}
                    }
                    if(!covered)continue;
                    bool duplicate=false;for(double candidate:candidates)if(std::abs(candidate-distance)<0.01){duplicate=true;break;}
                    if(!duplicate)candidates.push_back(distance);
                }
                auto projected_area=[&](const Polygon &poly) {
                    double area=0;for(size_t i=1;i+1<poly.size();i++)area+=(poly[i]-poly[0]).cross(poly[i+1]-poly[0]).dot(normal);
                    return std::abs(area)*0.5;
                };
                const double aperture_area=projected_area(aperture);
                auto coverage=[&](double distance,double &lo,double &hi) {
                    double area=0;lo=1e20;hi=-1e20;
                    for(const Polygon &piece:pieces) {
                        if(piece.size()<3)continue;
                        const Vector3 fn=(piece[1]-piece[0]).cross(piece[2]-piece[0]).normalized();
                        const double alignment=fn.dot(normal);if(std::abs(alignment)<0.95)continue;
                        if(std::abs(fn.dot(piece[0]-center)/alignment-distance)>0.01)continue;
                        Polygon projected=piece;
                        for(const auto &side:sides)projected=split(projected,side.first,side.second,true);
                        area+=projected_area(projected);
                        for(const Vector3 &v:projected){const double depth=normal.dot(v)-offset;lo=std::min(lo,depth);hi=std::max(hi,depth);}
                    }
                    return aperture_area>1e-8&&area/aperture_area>=0.9&&lo>=-limit&&hi<=limit;
                };
                // A small jamb or nearby prop is not a closure sheet. Source
                // shell closures cover essentially the whole authored opening.
                for(double candidate:candidates){double lo,hi;if(coverage(candidate,lo,hi)){selected.push_back(candidate);behind=std::max(behind,-lo+0.005);ahead=std::max(ahead,hi+0.005);}}
            }
            std::vector<std::pair<Vector3,double>> planes={{normal,offset-behind},{-normal,-offset-ahead}};
            planes.insert(planes.end(),sides.begin(),sides.end());
            std::vector<Polygon> next;
            for(const Polygon &piece:pieces) {
                if(piece.size()<3)continue;
                const Vector3 face_normal=(piece[1]-piece[0]).cross(piece[2]-piece[0]).normalized();
                if(std::abs(face_normal.dot(normal))<0.95){next.push_back(piece);continue;}
                const double face_distance=face_normal.dot(piece[0]-center)/face_normal.dot(normal);
                bool closure=std::abs(face_distance)<=0.1;
                for(double candidate:selected)if(std::abs(face_distance-candidate)<=0.01){closure=true;break;}
                if(!closure){next.push_back(piece);continue;}
                Polygon remainder=piece;
                for(const auto &plane:planes) {
                    Polygon outside=split(remainder,plane.first,plane.second,false);
                    if(outside.size()>=3)next.push_back(std::move(outside));
                    remainder=split(remainder,plane.first,plane.second,true);
                    if(remainder.size()<3)break;
                }
            }
            pieces=std::move(next);
        }
        PackedVector3Array faces;const Transform3D inverse=transform.affine_inverse();
        for(const Polygon &poly:pieces)for(size_t i=1;i+1<poly.size();i++) {
            if((poly[i]-poly[0]).cross(poly[i+1]-poly[0]).length_squared()<1e-12)continue;
            faces.push_back(inverse.xform(poly[0]));faces.push_back(inverse.xform(poly[i]));faces.push_back(inverse.xform(poly[i+1]));
        }
        Ref<ConcavePolygonShape3D> clipped;clipped.instantiate();clipped->set_faces(faces);clipped->set_backface_collision_enabled(true);
        item["shape"]=clipped;result[shape_index]=item;
    }
    return result;
}
