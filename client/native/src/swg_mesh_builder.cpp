#include "swg_mesh_builder.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <cmath>
#include <limits>
#include <vector>

namespace godot {
namespace {

bool number(const Variant &value, double &result) {
    if (value.get_type() != Variant::INT && value.get_type() != Variant::FLOAT) {
        return false;
    }
    result = static_cast<double>(value);
    return std::isfinite(result) && std::abs(result) <= std::numeric_limits<float>::max();
}

bool get_array(const Dictionary &source, const char *key, Array &result) {
    const Variant value = source.get(key, Array());
    if (value.get_type() != Variant::ARRAY) {
        return false;
    }
    result = value;
    return true;
}

bool vec3_array(const Array &source, PackedVector3Array &result) {
    if (source.is_empty()) {
        return true;
    }
    const bool nested = source[0].get_type() == Variant::ARRAY;
    if (!nested && source.size() % 3 != 0) {
        return false;
    }
    const int64_t count = nested ? source.size() : source.size() / 3;
    result.resize(count);
    Vector3 *destination = result.ptrw();
    for (int64_t i = 0; i < count; ++i) {
        Array row;
        if (nested) {
            if (source[i].get_type() != Variant::ARRAY) {
                return false;
            }
            row = source[i];
            if (row.size() != 3) {
                return false;
            }
        }
        double x, y, z;
        const Array &values = nested ? row : source;
        const int64_t start = nested ? 0 : i * 3;
        if (!number(values[start], x) || !number(values[start + 1], y) || !number(values[start + 2], z)) {
            return false;
        }
        destination[i] = Vector3(x, y, z);
    }
    return true;
}

bool surface_arrays(const Dictionary &surface, Array &arrays) {
    Array source_vertices, source_normals, source_uv, source_colors, source_indices;
    if (!get_array(surface, "vertices", source_vertices) || !get_array(surface, "normals", source_normals) ||
        !get_array(surface, "uv", source_uv) || !get_array(surface, "colors", source_colors) ||
        !get_array(surface, "indices", source_indices)) {
        return false;
    }
    PackedVector3Array vertices, normals;
    if (!vec3_array(source_vertices, vertices) || vertices.size() < 3 || !vec3_array(source_normals, normals)) {
        return false;
    }
    const int64_t count = vertices.size();
    arrays.resize(Mesh::ARRAY_MAX);
    arrays[Mesh::ARRAY_VERTEX] = vertices;
    if (!normals.is_empty()) {
        if (normals.size() != count) {
            return false;
        }
        arrays[Mesh::ARRAY_NORMAL] = normals;
    }
    if (!source_uv.is_empty()) {
        if (source_uv.size() != count * 2) {
            return false;
        }
        PackedVector2Array uv;
        uv.resize(count);
        Vector2 *destination = uv.ptrw();
        for (int64_t i = 0; i < count; ++i) {
            double u, v;
            if (!number(source_uv[i * 2], u) || !number(source_uv[i * 2 + 1], v)) {
                return false;
            }
            destination[i] = Vector2(u, v);
        }
        arrays[Mesh::ARRAY_TEX_UV] = uv;
    }
    if (!source_colors.is_empty()) {
        if (source_colors.size() != count * 4) {
            return false;
        }
        PackedColorArray colors;
        colors.resize(count);
        Color *destination = colors.ptrw();
        for (int64_t i = 0; i < count; ++i) {
            double r, g, b, a;
            if (!number(source_colors[i * 4], r) || !number(source_colors[i * 4 + 1], g) ||
                !number(source_colors[i * 4 + 2], b) || !number(source_colors[i * 4 + 3], a)) {
                return false;
            }
            destination[i] = Color(r, g, b, a);
        }
        arrays[Mesh::ARRAY_COLOR] = colors;
    }
    if (!source_indices.is_empty()) {
        if (source_indices.size() % 3 != 0) {
            return false;
        }
        PackedInt32Array indices;
        indices.resize(source_indices.size());
        int32_t *destination = indices.ptrw();
        for (int64_t i = 0; i < source_indices.size(); ++i) {
            double index;
            if (!number(source_indices[i], index) || std::floor(index) != index || index < 0 ||
                index >= count || index > std::numeric_limits<int32_t>::max()) {
                return false;
            }
            destination[i] = static_cast<int32_t>(index);
        }
        arrays[Mesh::ARRAY_INDEX] = indices;
    } else if (count % 3 != 0) {
        return false;
    }
    return true;
}

bool skin_arrays(const Dictionary &surface, Array &arrays, int64_t bone_count, uint64_t &flags) {
    Array source_bones, source_weights;
    if (!get_array(surface, "bones", source_bones) || !get_array(surface, "weights", source_weights)) return false;
    if (source_bones.is_empty() && source_weights.is_empty()) return true;
    const PackedVector3Array vertices = arrays[Mesh::ARRAY_VERTEX];
    const int64_t count = vertices.size();
    if (source_bones.size() != source_weights.size() || source_bones.size() % count) return false;
    const int64_t influences = source_bones.size() / count;
    if (influences != 4 && influences != 8) return false;
    PackedInt32Array bones;
    PackedFloat32Array weights;
    bones.resize(source_bones.size());
    weights.resize(source_weights.size());
    for (int64_t i = 0; i < count; ++i) {
        double total = 0.0;
        for (int64_t j = 0; j < influences; ++j) {
            const int64_t index = i * influences + j;
            double bone, weight;
            if (!number(source_bones[index], bone) || std::floor(bone) != bone || bone < 0 ||
                bone >= bone_count || !number(source_weights[index], weight) || weight < 0) return false;
            bones[index] = int32_t(bone);
            weights[index] = float(weight);
            total += weight;
        }
        if (total < 1e-8) return false;
        for (int64_t j = 0; j < influences; ++j) weights[i * influences + j] /= total;
    }
    arrays[Mesh::ARRAY_BONES] = bones;
    arrays[Mesh::ARRAY_WEIGHTS] = weights;
    if (influences == 8) flags |= Mesh::ARRAY_FLAG_USE_8_BONE_WEIGHTS;
    return true;
}

bool morph_arrays(const Dictionary &source, const Array &base, Array &result) {
    const PackedVector3Array base_vertices = base[Mesh::ARRAY_VERTEX];
    const int64_t count = base_vertices.size();
    Array raw;
    PackedVector3Array positions;
    if (!get_array(source, "vertices", raw) || !vec3_array(raw, positions)) return false;
    if (positions.is_empty()) { positions.resize(count); positions.fill(Vector3()); }
    if (positions.size() != count) return false;
    result.resize(Mesh::ARRAY_MAX);
    result[Mesh::ARRAY_VERTEX] = positions;
    if (base[Mesh::ARRAY_NORMAL].get_type() != Variant::NIL) {
        PackedVector3Array normals;
        if (!get_array(source, "normals", raw) || !vec3_array(raw, normals)) return false;
        if (normals.is_empty()) { normals.resize(count); normals.fill(Vector3()); }
        if (normals.size() != count) return false;
        result[Mesh::ARRAY_NORMAL] = normals;
    }
    return true;
}

} // namespace

void SwgMeshBuilder::_bind_methods() {
    ClassDB::bind_method(D_METHOD("create_mesh", "surfaces"), &SwgMeshBuilder::create_mesh);
    ClassDB::bind_method(D_METHOD("prepare_mesh", "surfaces"), &SwgMeshBuilder::prepare_mesh);
    ClassDB::bind_method(D_METHOD("create_prepared_mesh", "arrays"), &SwgMeshBuilder::create_prepared_mesh);
    ClassDB::bind_method(D_METHOD("create_avatar_mesh", "definition"), &SwgMeshBuilder::create_avatar_mesh);
    ClassDB::bind_method(D_METHOD("partition_avatar", "definition", "hidden_bones", "threshold"), &SwgMeshBuilder::partition_avatar, DEFVAL(0.45));
    ClassDB::bind_method(D_METHOD("create_terrain_mesh", "data", "skirt_depth"), &SwgMeshBuilder::create_terrain_mesh);
    ClassDB::bind_method(D_METHOD("create_terrain_collision", "data"), &SwgMeshBuilder::create_terrain_collision);
    ClassDB::bind_method(D_METHOD("create_collision", "mesh"), &SwgMeshBuilder::create_collision);
}

Dictionary SwgMeshBuilder::partition_avatar(const Dictionary &definition, const Array &hidden_bones, double threshold) const {
    Dictionary result;
    const int64_t bone_count = definition.get("bone_count", 0);
    if (bone_count <= 0 || !std::isfinite(threshold) || threshold <= 0.0 || threshold > 1.0) return result;
    std::vector<bool> hidden(static_cast<size_t>(bone_count), false);
    for (int64_t i = 0; i < hidden_bones.size(); ++i) {
        double value;
        if (!number(hidden_bones[i], value) || std::floor(value) != value || value < 0 || value >= bone_count) return result;
        hidden[static_cast<size_t>(value)] = true;
    }
    Array surfaces;
    if (!get_array(definition, "surfaces", surfaces)) return result;
    Array visible_surfaces, hidden_surfaces;
    int64_t visible_triangles = 0, hidden_triangles = 0;
    for (int64_t si = 0; si < surfaces.size(); ++si) {
        if (surfaces[si].get_type() != Variant::DICTIONARY) return Dictionary();
        const Dictionary surface = surfaces[si];
        Array vertices, joints, weights, indices, zones;
        if (!get_array(surface, "vertices", vertices) || !get_array(surface, "bones", joints) ||
            !get_array(surface, "weights", weights) || !get_array(surface, "indices", indices) ||
            !get_array(surface, "triangle_zones", zones) || vertices.is_empty()) return Dictionary();
        const bool nested = vertices[0].get_type() == Variant::ARRAY;
        const int64_t count = nested ? vertices.size() : vertices.size() / 3;
        if (count < 3 || (!nested && vertices.size() % 3) || joints.size() != weights.size() ||
            joints.size() % count) return Dictionary();
        const int64_t width = joints.size() / count;
        if (width != 4 && width != 8) return Dictionary();
        std::vector<bool> hidden_vertices(static_cast<size_t>(count), false);
        for (int64_t vi = 0; vi < count; ++vi) {
            double total = 0.0, hidden_weight = 0.0;
            for (int64_t influence = 0; influence < width; ++influence) {
                const int64_t offset = vi * width + influence;
                double joint, weight;
                if (!number(joints[offset], joint) || std::floor(joint) != joint || joint < 0 || joint >= bone_count ||
                    !number(weights[offset], weight) || weight < 0) return Dictionary();
                total += weight;
                if (hidden[static_cast<size_t>(joint)]) hidden_weight += weight;
            }
            if (total <= 1e-8) return Dictionary();
            hidden_vertices[static_cast<size_t>(vi)] = hidden_weight / total >= threshold;
        }
        const int64_t index_count = indices.is_empty() ? count : indices.size();
        if (index_count % 3) return Dictionary();
        Array visible_indices, hidden_indices, visible_zones, hidden_zones;
        const bool have_zones = zones.size() == index_count / 3;
        for (int64_t start = 0; start < index_count; start += 3) {
            int64_t triangle[3];
            bool hide = false;
            for (int64_t corner = 0; corner < 3; ++corner) {
                double index = start + corner;
                if (!indices.is_empty() && !number(indices[start + corner], index)) return Dictionary();
                if (std::floor(index) != index || index < 0 || index >= count) return Dictionary();
                triangle[corner] = static_cast<int64_t>(index);
                hide = hide || hidden_vertices[static_cast<size_t>(triangle[corner])];
            }
            Array &destination = hide ? hidden_indices : visible_indices;
            for (int corner = 0; corner < 3; ++corner) destination.append(triangle[corner]);
            if (have_zones) (hide ? hidden_zones : visible_zones).append(zones[start / 3]);
            if (hide) ++hidden_triangles; else ++visible_triangles;
        }
        // Vertices, weights and morph deltas remain shared and unchanged. Only
        // triangle ownership changes, so combining both camera layers exactly
        // reconstructs the original source mesh without duplicate triangles.
        if (!visible_indices.is_empty()) {
            Dictionary part = surface.duplicate(false);
            part["indices"] = visible_indices;
            part["triangle_zones"] = visible_zones;
            visible_surfaces.append(part);
        }
        if (!hidden_indices.is_empty()) {
            Dictionary part = surface.duplicate(false);
            part["indices"] = hidden_indices;
            part["triangle_zones"] = hidden_zones;
            hidden_surfaces.append(part);
        }
    }
    Dictionary body = definition.duplicate(false), head = definition.duplicate(false), statistics;
    body["surfaces"] = visible_surfaces;
    head["surfaces"] = hidden_surfaces;
    statistics["body_triangles"] = visible_triangles;
    statistics["head_triangles"] = hidden_triangles;
    statistics["threshold"] = threshold;
    result["body"] = body;
    result["head"] = head;
    result["statistics"] = statistics;
    return result;
}

Dictionary SwgMeshBuilder::prepare_mesh(const Array &surfaces) const {
    // Pure packed-data conversion. Safe for a private background worker: no
    // RenderingServer, PhysicsServer, scene nodes or shared mutable resources.
    if(surfaces.is_empty())return Dictionary();
    Array prepared;
    PackedVector3Array faces;
    int64_t bytes=0;
    for(int64_t i=0;i<surfaces.size();++i) {
        if(surfaces[i].get_type()!=Variant::DICTIONARY)return Dictionary();
        Array arrays;
        if(!surface_arrays(surfaces[i],arrays))return Dictionary();
        PackedVector3Array vertices=arrays[Mesh::ARRAY_VERTEX];
        if(arrays[Mesh::ARRAY_COLOR].get_type()==Variant::NIL) {
            PackedVector3Array normals=arrays[Mesh::ARRAY_NORMAL];
            PackedColorArray colors;colors.resize(vertices.size());
            for(int64_t v=0;v<vertices.size();++v) {
                float up=normals.size()==vertices.size()?normals[v].normalized().y:1.0f;
                float light=.68f+.32f*std::max(0.0f,up);
                colors.set(v,Color(light,light,light,1));
            }
            arrays[Mesh::ARRAY_COLOR]=colors;
        }
        PackedInt32Array indices;
        if(arrays[Mesh::ARRAY_INDEX].get_type()!=Variant::NIL)indices=arrays[Mesh::ARRAY_INDEX];
        int64_t count=indices.is_empty()?vertices.size():indices.size();
        int64_t start=faces.size();faces.resize(start+count);
        Vector3 *out=faces.ptrw();
        for(int64_t j=0;j<count;++j)out[start+j]=vertices[indices.is_empty()?j:indices[j]];
        // Conservative vertex/index/normal/UV/color plus triangle storage.
        bytes+=vertices.size()*64+indices.size()*4+count*12;
        prepared.append(arrays);
    }
    Dictionary result;result["arrays"]=prepared;result["faces"]=faces;result["bytes"]=bytes;
    return result;
}

Ref<ArrayMesh> SwgMeshBuilder::create_prepared_mesh(const Array &arrays) const {
    if(arrays.is_empty())return Ref<ArrayMesh>();
    Ref<ArrayMesh> mesh;mesh.instantiate();
    for(int64_t i=0;i<arrays.size();++i) {
        if(arrays[i].get_type()!=Variant::ARRAY)return Ref<ArrayMesh>();
        const Array surface=arrays[i];
        if(surface.size()!=Mesh::ARRAY_MAX)return Ref<ArrayMesh>();
        mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES,surface);
    }
    return mesh;
}

Ref<ArrayMesh> SwgMeshBuilder::create_mesh(const Array &surfaces) const {
    if (surfaces.is_empty()) {
        return Ref<ArrayMesh>();
    }
    Ref<ArrayMesh> mesh;
    mesh.instantiate();
    for (int64_t i = 0; i < surfaces.size(); ++i) {
        Array arrays;
        if (surfaces[i].get_type() != Variant::DICTIONARY || !surface_arrays(surfaces[i], arrays)) {
            UtilityFunctions::push_error("SwgMeshBuilder: malformed surface at index ", i);
            return Ref<ArrayMesh>();
        }
        // Preserve original authored baked colors. Uncolored source surfaces
        // receive a fixed sky-hemisphere vertex bake at mesh construction.
        if (arrays[Mesh::ARRAY_COLOR].get_type()==Variant::NIL) {
            const PackedVector3Array vertices = arrays[Mesh::ARRAY_VERTEX];
            const PackedVector3Array normals = arrays[Mesh::ARRAY_NORMAL];
            PackedColorArray colors; colors.resize(vertices.size());
            for(int64_t vertex=0;vertex<vertices.size();++vertex) {
                const float up=normals.size()==vertices.size()?normals[vertex].normalized().y:1.0f;
                const float light=0.68f+0.32f*MAX(0.0f,up);
                colors.set(vertex,Color(light,light,light,1));
            }
            arrays[Mesh::ARRAY_COLOR]=colors;
        }
        // Keep source order exactly: the loader assigns material i to surface i.
        mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);
        if (mesh->get_surface_count() != i + 1) {
            UtilityFunctions::push_error("SwgMeshBuilder: engine rejected surface at index ", i);
            return Ref<ArrayMesh>();
        }
    }
    return mesh;
}

Ref<ConcavePolygonShape3D> SwgMeshBuilder::create_collision(const Ref<ArrayMesh> &mesh) const {
    if (mesh.is_null() || mesh->get_surface_count() == 0) {
        return Ref<ConcavePolygonShape3D>();
    }
    Ref<ConcavePolygonShape3D> shape = mesh->create_trimesh_shape();
    if (shape.is_valid()) {
        // Matching front-face collision prevents the exterior hull's backfaces
        // from becoming invisible walls inside the imported portalized rooms.
        shape->set_backface_collision_enabled(false);
    }
    return shape;
}

Ref<ArrayMesh> SwgMeshBuilder::create_avatar_mesh(const Dictionary &definition) const {
    const Array surfaces = definition.get("surfaces", Array());
    const Array names = definition.get("blend_shapes", Array());
    const int64_t bone_count = definition.get("bone_count", int64_t(0));
    if (surfaces.is_empty() || bone_count < 0 || bone_count > std::numeric_limits<int32_t>::max()) return Ref<ArrayMesh>();
    Ref<ArrayMesh> mesh;
    mesh.instantiate();
    mesh->set_blend_shape_mode(Mesh::BLEND_SHAPE_MODE_RELATIVE);
    for (int64_t i = 0; i < names.size(); ++i) mesh->add_blend_shape(String(names[i]));
    for (int64_t i = 0; i < surfaces.size(); ++i) {
        const Dictionary surface = surfaces[i];
        Array arrays;
        uint64_t flags = 0;
        if (!surface_arrays(surface, arrays) || !skin_arrays(surface, arrays, bone_count, flags)) {
            UtilityFunctions::push_error("SwgMeshBuilder: invalid avatar skin/surface ", i);
            return Ref<ArrayMesh>();
        }
        // Fixed bind-pose vertex irradiance for animated meshes. Skinning moves
        // the baked values with the skin; no runtime directional lights/shadows.
        const PackedVector3Array baked_normals = arrays[Mesh::ARRAY_NORMAL];
        const PackedVector3Array baked_vertices = arrays[Mesh::ARRAY_VERTEX];
        PackedColorArray baked_colors;
        baked_colors.resize(baked_vertices.size());
        const Vector3 baked_sun = Vector3(-0.35,0.82,-0.45).normalized();
        for (int64_t vertex=0; vertex<baked_vertices.size(); ++vertex) {
            const Vector3 n = baked_normals.size()==baked_vertices.size()?baked_normals[vertex].normalized():Vector3(0,1,0);
            const float irradiance = 0.62f + 0.16f*MAX(0.0f,n.y) + 0.22f*MAX(0.0f,n.dot(baked_sun));
            baked_colors.set(vertex,Color(irradiance,irradiance,irradiance,1));
        }
        arrays[Mesh::ARRAY_COLOR] = baked_colors;
        const Dictionary source_morphs = surface.get("blend_shapes", Dictionary());
        TypedArray<Array> morphs;
        for (int64_t j = 0; j < names.size(); ++j) {
            Array morph;
            const Dictionary source = source_morphs.get(names[j], Dictionary());
            if (!morph_arrays(source, arrays, morph)) {
                UtilityFunctions::push_error("SwgMeshBuilder: invalid avatar morph ", names[j]);
                return Ref<ArrayMesh>();
            }
            morphs.push_back(morph);
        }
        mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays, morphs, Dictionary(), BitField<Mesh::ArrayFormat>(flags));
        if (mesh->get_surface_count() != i + 1) return Ref<ArrayMesh>();
    }
    return mesh;
}

} // namespace godot
