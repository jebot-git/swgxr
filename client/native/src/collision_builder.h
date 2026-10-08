#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/concave_polygon_shape3d.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
namespace godot {
class SwgCollisionBuilder : public RefCounted {
    GDCLASS(SwgCollisionBuilder,RefCounted)
protected: static void _bind_methods();
public:
    Array build_extent(const Dictionary &definition) const;
    Array build_cell_extent(const Dictionary &definition,const Array &portals,const Dictionary &floor) const;
    Ref<ConcavePolygonShape3D> build_floor(const Dictionary &cell) const;
};
}
