#include "interior_mask.h"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <vector>
#include <cmath>
#include <cstring>
using namespace godot;
namespace {
Vector3 point(const Array &values,int offset=0) {return Vector3(values[offset],values[offset+1],values[offset+2]);}
}
void SwgInteriorMask::_bind_methods() {
    ClassDB::bind_method(D_METHOD("rasterize","regions","chunk_origin","world_origin","size","resolution"),&SwgInteriorMask::rasterize,DEFVAL(128.0),DEFVAL(512));
}
Dictionary SwgInteriorMask::rasterize(const Array &regions,const Vector2 &chunk_origin,
                                     const Vector3 &world_origin,double size,int resolution) const {
    Dictionary result;result["valid"]=false;
    if(!chunk_origin.is_finite()||!world_origin.is_finite()||!std::isfinite(size)||size<=0||resolution<8||resolution>2048)return result;
    std::vector<float> pixels;
    int cells=0,triangles=0,covered=0;
    for(int64_t ri=0;ri<regions.size();ri++) {
        const Dictionary region=regions[ri];
        const Transform3D transform=region.get("transform",Transform3D());
        const Dictionary definitions=region.get("cells",Dictionary());
        const Array keys=definitions.keys();
        for(int64_t ci=0;ci<keys.size();ci++) {
            const Dictionary cell=definitions[keys[ci]];
            if(bool(cell.get("is_exterior",false)))continue;
            const Array minimum=cell.get("bounds_min",Array()),maximum=cell.get("bounds_max",Array());
            const Array vertices=cell.get("floor_vertices",Array()),indices=cell.get("floor_indices",Array());
            if(minimum.size()!=3||maximum.size()!=3||vertices.size()%3||indices.size()%3||indices.is_empty())continue;
            const Vector3 low=point(minimum),high=point(maximum);
            Vector3 low_world(1e20,1e20,1e20),high_world(-1e20,-1e20,-1e20);
            for(int corner=0;corner<8;corner++) {
                const Vector3 p=transform.xform(Vector3(corner&1?high.x:low.x,corner&2?high.y:low.y,corner&4?high.z:low.z));
                low_world=low_world.min(p);high_world=high_world.max(p);
            }
            if(high_world.x+world_origin.x<chunk_origin.x||low_world.x+world_origin.x>chunk_origin.x+size||
                world_origin.z-low_world.z<chunk_origin.y||world_origin.z-high_world.z>chunk_origin.y+size)continue;
            cells++;
            for(int64_t ti=0;ti<indices.size();ti+=3) {
                Vector3 p[3];Vector2 uv[3];bool valid=true;
                for(int j=0;j<3;j++) {
                    const int index=indices[ti+j];
                    if(index<0||index>=vertices.size()/3){valid=false;break;}
                    p[j]=transform.xform(point(vertices,index*3));
                    uv[j]=Vector2((p[j].x+world_origin.x-chunk_origin.x)*resolution/size,
                                  (world_origin.z-p[j].z-chunk_origin.y)*resolution/size);
                    if(!p[j].is_finite()){valid=false;break;}
                }
                if(!valid)continue;
                const Vector2 u=uv[1]-uv[0],v=uv[2]-uv[0];const double determinant=u.cross(v);
                const double padding=0.30*resolution/size;
                if(std::abs(determinant)<1e-8)continue;
                const int min_x=MAX(0,static_cast<int>(std::floor(MIN(uv[0].x,MIN(uv[1].x,uv[2].x))-padding-0.5)));
                const int max_x=MIN(resolution-1,static_cast<int>(std::ceil(MAX(uv[0].x,MAX(uv[1].x,uv[2].x))+padding-0.5)));
                const int min_y=MAX(0,static_cast<int>(std::floor(MIN(uv[0].y,MIN(uv[1].y,uv[2].y))-padding-0.5)));
                const int max_y=MIN(resolution-1,static_cast<int>(std::ceil(MAX(uv[0].y,MAX(uv[1].y,uv[2].y))+padding-0.5)));
                if(min_x>max_x||min_y>max_y)continue;
                triangles++;
                if(pixels.empty()) {
                    pixels.resize(resolution*resolution*2);
                    for(size_t i=0;i<pixels.size();i+=2){pixels[i]=1e20f;pixels[i+1]=-1e20f;}
                }
                const double tolerance_b=padding*v.length()/std::abs(determinant);
                const double tolerance_c=padding*u.length()/std::abs(determinant);
                const double tolerance_sum=padding*(u-v).length()/std::abs(determinant);
                const double pixel_size=size/resolution;
                for(int y=min_y;y<=max_y;y++)for(int x=min_x;x<=max_x;x++) {
                    // Cover wall thickness and raster quantization without
                    // expanding beyond the original cell mesh's own bounds.
                    const double world_x=chunk_origin.x+(x+0.5)*pixel_size-world_origin.x;
                    const double world_z=world_origin.z-chunk_origin.y-(y+0.5)*pixel_size;
                    if(world_x<low_world.x||world_x>high_world.x||world_z<low_world.z||world_z>high_world.z)continue;
                    const Vector2 d=Vector2(x+0.5,y+0.5)-uv[0];
                    const double b=d.cross(v)/determinant,c=u.cross(d)/determinant;
                    if(b < -tolerance_b || c < -tolerance_c || b+c > 1+tolerance_sum)continue;
                    const double floor=p[0].y+b*(p[1].y-p[0].y)+c*(p[2].y-p[0].y);
                    const size_t offset=(y*resolution+x)*2;
                    if(pixels[offset]>1e19)covered++;
                    pixels[offset]=MIN(pixels[offset],static_cast<float>(floor-0.06));
                    pixels[offset+1]=MAX(pixels[offset+1],static_cast<float>(high_world.y+0.1));
                }
            }
        }
    }
    result["valid"]=true;result["wall_padding_m"]=0.30;result["cells"]=cells;result["triangles"]=triangles;result["covered_texels"]=covered;
    if(covered>0) {
        PackedByteArray bytes;bytes.resize(pixels.size()*sizeof(float));std::memcpy(bytes.ptrw(),pixels.data(),bytes.size());
        result["image"]=Image::create_from_data(resolution,resolution,false,Image::FORMAT_RGF,bytes);
    }
    return result;
}
