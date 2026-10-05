#include "swg_mesh_builder.h"
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <algorithm>
#include <array>
#include <cmath>
#include <map>
#include <vector>

namespace godot {
namespace {
struct TerrainData {
    PackedVector3Array vertices, normals;
    PackedVector2Array uvs;
    PackedInt32Array indices;
    PackedFloat32Array ids;
    PackedColorArray weights, tints;
    bool read(const Dictionary &data) {
        vertices=data.get("vertices",PackedVector3Array()); normals=data.get("normals",PackedVector3Array());
        uvs=data.get("uvs",PackedVector2Array()); indices=data.get("indices",PackedInt32Array());
        ids=data.get("shader_ids",PackedFloat32Array()); weights=data.get("shader_weights",PackedColorArray());
        tints=data.get("tints",PackedColorArray());
        const int n=vertices.size();
        if (!n || normals.size()!=n || uvs.size()!=n || ids.size()!=4*n || weights.size()!=n || indices.size()%3) return false;
        for (int i=0;i<indices.size();++i) if (indices[i]<0 || indices[i]>=n) return false;
        return true;
    }
};
}

Ref<ArrayMesh> SwgMeshBuilder::create_terrain_mesh(const Dictionary &data, double skirt_depth) const {
    TerrainData in; if (!in.read(data) || in.indices.is_empty()) return {};
    PackedVector3Array vertices, normals;
    PackedVector2Array uvs;
    PackedColorArray weights;
    PackedFloat32Array ids, tints, tangents;
    // One fixed family set per triangle prevents interpolating texture IDs.
    // Weights and smooth source normals still interpolate over the surface.
    auto triangle = [&](int a,int b,int c,const Vector3 &da,const Vector3 &db,const Vector3 &dc) {
        std::array<int,3> source={a,b,c}; std::array<Vector3,3> offset={da,db,dc};
        std::map<int,float> total;
        for (int index:source) for(int j=0;j<4;++j) total[int(in.ids[index*4+j])]+=in.weights[index][j];
        std::vector<std::pair<int,float>> families(total.begin(),total.end());
        std::stable_sort(families.begin(),families.end(),[](auto a,auto b){return a.second>b.second;});
        if(families.size()>4) families.resize(4);
        for(int k=0;k<3;++k) {
            const int index=source[k];
            vertices.push_back(in.vertices[index]+offset[k]); normals.push_back(in.normals[index]); uvs.push_back(in.uvs[index]);
            Color w(0,0,0,0); float sum=0;
            for(int j=0;j<int(families.size());++j) {
                ids.push_back(float(families[j].first));
                for(int l=0;l<4;++l) if(int(in.ids[index*4+l])==families[j].first) w[j]+=in.weights[index][l];
                sum+=w[j];
            }
            for(int j=families.size();j<4;++j) ids.push_back(0);
            if(sum>0) for(int j=0;j<4;++j) w[j]/=sum;
            weights.push_back(w);
            const Color tint=in.tints.size()==in.vertices.size()?in.tints[index]:Color(1,1,1,1);
            // Bake a fixed broad daylight response once per streamed mesh.
            // Day/night changes only blend this vertex bake; no live lights.
            for(int j=0;j<3;++j)tints.push_back(tint[j]);
            const Vector3 sun=Vector3(-0.35,0.82,-0.45).normalized();
            tints.push_back(0.52 + 0.20 * MAX(0.0f,in.normals[index].y) + 0.28 * MAX(0.0f,in.normals[index].dot(sun)));
            Vector3 tangent=(Vector3(1,0,0)-in.normals[index]*in.normals[index].x).normalized();
            tangents.push_back(tangent.x);tangents.push_back(tangent.y);tangents.push_back(tangent.z);tangents.push_back(1);
        }
    };
    for(int i=0;i<in.indices.size();i+=3) triangle(in.indices[i],in.indices[i+1],in.indices[i+2],Vector3(),Vector3(),Vector3());
    // Render-only skirts close cracks at LOD boundaries. Collision retains the
    // exact unskirted source triangles, so skirts never become invisible walls.
    if(skirt_depth>0) {
        const Vector3 down(0,-skirt_depth,0);
        const double size=double(data.get("size",128.0));
        std::map<std::pair<int,int>,bool> emitted;
        for(int i=0;i<in.indices.size();i+=3)for(int j=0;j<3;++j) {
            const int a=in.indices[i+j],b=in.indices[i+(j+1)%3];
            const Vector3 p=in.vertices[a],q=in.vertices[b];
            const bool border=(std::abs(p.x)<1e-4&&std::abs(q.x)<1e-4)||
                (std::abs(p.x-size)<1e-4&&std::abs(q.x-size)<1e-4)||
                (std::abs(p.z)<1e-4&&std::abs(q.z)<1e-4)||
                (std::abs(p.z+size)<1e-4&&std::abs(q.z+size)<1e-4);
            const auto key=std::minmax(a,b);
            if(!border || emitted.count(key))continue;emitted[key]=true;
            triangle(a,b,b,Vector3(),Vector3(),down);triangle(a,b,a,Vector3(),down,down);
        }
    }
    Array arrays;arrays.resize(Mesh::ARRAY_MAX);
    arrays[Mesh::ARRAY_VERTEX]=vertices;arrays[Mesh::ARRAY_NORMAL]=normals;arrays[Mesh::ARRAY_TANGENT]=tangents;
    arrays[Mesh::ARRAY_TEX_UV]=uvs;arrays[Mesh::ARRAY_COLOR]=weights;
    arrays[Mesh::ARRAY_CUSTOM0]=ids;arrays[Mesh::ARRAY_CUSTOM1]=tints;
    uint64_t format=(uint64_t(Mesh::ARRAY_CUSTOM_RGBA_FLOAT)<<Mesh::ARRAY_FORMAT_CUSTOM0_SHIFT) | (uint64_t(Mesh::ARRAY_CUSTOM_RGBA_FLOAT)<<Mesh::ARRAY_FORMAT_CUSTOM1_SHIFT);
    Ref<ArrayMesh> mesh;mesh.instantiate();
    mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES,arrays,{},Dictionary(),BitField<Mesh::ArrayFormat>(format));
    return mesh->get_surface_count()?mesh:Ref<ArrayMesh>();
}
Ref<ConcavePolygonShape3D> SwgMeshBuilder::create_terrain_collision(const Dictionary &data) const {
    TerrainData in;if(!in.read(data)||in.indices.is_empty())return {};
    PackedVector3Array faces;faces.resize(in.indices.size());
    for(int i=0;i<in.indices.size();++i) faces[i]=in.vertices[in.indices[i]];
    Ref<ConcavePolygonShape3D> shape;shape.instantiate();shape->set_faces(faces);shape->set_backface_collision_enabled(false);return shape;
}
}
