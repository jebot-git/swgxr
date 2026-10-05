#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <vector>

namespace godot {
// Classify the observer against original SWG floor triangles, not room AABBs.
class SwgCellClassifier : public RefCounted {
    GDCLASS(SwgCellClassifier, RefCounted)
    struct Triangle { Vector3 a, b, c; };
    struct Portal { String target; std::vector<Vector3> vertices; };
    struct Cell {
        String id, name;
        int64_t building_id;
        bool exterior = false;
        std::vector<Portal> portals;
        Vector3 minimum, maximum;
        std::vector<Triangle> floor;
    };
    std::vector<Cell> cells;
protected:
    static void _bind_methods();
public:
    void configure(const Dictionary &definitions);
    Dictionary classify(const Vector3 &position) const;
    Dictionary advance(const Vector3 &from, const Vector3 &to, const String &current_cell) const;
};
}
