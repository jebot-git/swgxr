#pragma once

#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/multi_mesh.hpp>
#include <godot_cpp/classes/concave_polygon_shape3d.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/transform3d.hpp>

namespace godot {

// Converts the existing locally generated JSON surface schema into shared
// engine meshes. Materials and scene placement remain presentation concerns.
class SwgMeshBuilder : public RefCounted {
    GDCLASS(SwgMeshBuilder, RefCounted)

protected:
    static void _bind_methods();

public:
    Ref<MultiMesh> create_instances(const Ref<ArrayMesh> &mesh, const Array &instances) const;
    Dictionary ray_mesh(const PackedVector3Array &faces, const Transform3D &pose, const Vector3 &origin, const Vector3 &direction, double reach) const;
    Ref<ArrayMesh> create_mesh(const Array &surfaces) const;
    Dictionary prepare_mesh(const Array &surfaces) const;
    Ref<ArrayMesh> create_prepared_mesh(const Array &arrays) const;
    Ref<ArrayMesh> create_avatar_mesh(const Dictionary &definition) const;
    Dictionary partition_avatar(const Dictionary &definition, const Array &hidden_bones, double threshold) const;
    Ref<ArrayMesh> create_terrain_mesh(const Dictionary &data, double skirt_depth) const;
    Ref<ConcavePolygonShape3D> create_terrain_collision(const Dictionary &data) const;
    Ref<ConcavePolygonShape3D> create_collision(const Ref<ArrayMesh> &mesh) const;
};

} // namespace godot
