#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
namespace godot {
class SwgInteriorMask : public RefCounted {
    GDCLASS(SwgInteriorMask, RefCounted)
protected:
    static void _bind_methods();
public:
    Dictionary rasterize(const Array &regions, const Vector2 &chunk_origin,
                         const Vector3 &world_origin, double size=128, int resolution=512) const;
};
}
