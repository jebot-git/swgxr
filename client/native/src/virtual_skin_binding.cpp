#include "virtual_skin_binding.h"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/object.hpp>
#include <unordered_set>
using namespace godot;
void SwgVirtualSkinBinding::_bind_methods() {
    ClassDB::bind_method(D_METHOD("configure","skeleton","skin","definitions"),&SwgVirtualSkinBinding::configure);
    ClassDB::bind_method(D_METHOD("update"),&SwgVirtualSkinBinding::update);
}
bool SwgVirtualSkinBinding::configure(Skeleton3D *skeleton,const Ref<Skin> &source_skin,const Array &definitions) {
    skeleton_id=0;skin.unref();groups.clear();
    if(!skeleton||source_skin.is_null()||definitions.is_empty())return false;
    std::unordered_set<int> virtual_bones;
    for(int64_t i=0;i<definitions.size();i++) {
        if(definitions[i].get_type()!=Variant::DICTIONARY)return false;
        const Dictionary definition=definitions[i];
        const int bone=definition.get("bone",-1);
        if(bone<0||bone>=skeleton->get_bone_count()||virtual_bones.count(bone))return false;
        virtual_bones.insert(bone);
    }
    for(int64_t i=0;i<definitions.size();i++) {
        const Dictionary definition=definitions[i];
        Group group;group.bone=definition["bone"];group.bind=-1;
        for(int j=0;j<source_skin->get_bind_count();j++)if(source_skin->get_bind_bone(j)==group.bone)group.bind=j;
        if(group.bind<0||definition.get("source_bones",Array()).get_type()!=Variant::ARRAY)return false;
        const Array source_bones=definition["source_bones"];
        if(source_bones.is_empty())return false;
        std::unordered_set<int> seen;
        for(int64_t j=0;j<source_bones.size();j++) {
            const int bone=source_bones[j];
            if(bone<0||bone>=skeleton->get_bone_count()||virtual_bones.count(bone)||seen.count(bone))return false;
            seen.insert(bone);
            int binding=-1;
            for(int k=0;k<source_skin->get_bind_count();k++)if(source_skin->get_bind_bone(k)==bone)binding=k;
            if(binding<0)return false;
            group.sources.push_back({bone,source_skin->get_bind_pose(binding)});
        }
        groups.push_back(std::move(group));
    }
    skeleton_id=skeleton->get_instance_id();skin=source_skin;return true;
}
Dictionary SwgVirtualSkinBinding::update() {
    Dictionary result;result["valid"]=false;
    Skeleton3D *skeleton=Object::cast_to<Skeleton3D>(ObjectDB::get_instance(skeleton_id));
    if(!skeleton||skin.is_null())return result;
    int matrices=0;
    for(const Group &group:groups) {
        Vector3 columns[3],origin;
        for(const Source &source:group.sources) {
            const Transform3D matrix=skeleton->get_bone_global_pose(source.bone)*source.inverse_bind;
            for(int i=0;i<3;i++)columns[i]+=matrix.basis.get_column(i);
            origin+=matrix.origin;matrices++;
        }
        const double count=static_cast<double>(group.sources.size());
        const Transform3D average(Basis(columns[0]/count,columns[1]/count,columns[2]/count),origin/count);
        // Multiplying the renderer's virtual bone pose by this bind yields the
        // exact mean skinning matrix even if the virtual root was repositioned.
        skin->set_bind_pose(group.bind,skeleton->get_bone_global_pose(group.bone).affine_inverse()*average);
    }
    result["valid"]=true;result["virtual_bones"]=static_cast<int>(groups.size());result["source_matrices"]=matrices;
    result["mode"]="exact_affine_uniform_residual";return result;
}
