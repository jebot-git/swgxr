#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/plane.hpp>
#include <vector>
namespace godot {
// Visibility only. Source cell membership and collision remain independent.
class SwgPortalVisibility : public RefCounted {
    GDCLASS(SwgPortalVisibility, RefCounted)
    struct Portal { int target = -1; std::vector<Vector3> vertices; };
    struct Cell { String id; int building = -1; bool exterior = false; std::vector<Portal> portals; };
    struct Building { int64_t id = 0; bool valid = true; std::vector<int> cells, roots; };
    std::vector<Cell> cells;
    std::vector<Building> buildings;
    Dictionary indices;
    bool configured = false;
    static std::vector<Vector3> clip(const std::vector<Vector3> &, const Plane &);
    bool walk(int cell, const Vector3 &eye, const std::vector<Plane> &planes, std::vector<int> &path,
        std::vector<bool> &visible, double margin, int &visits, int budget) const;
protected:
    static void _bind_methods();
public:
    void configure(const Dictionary &definitions);
    Dictionary solve(const Array &views, double margin = 0.25, int budget = 8192) const;
};
}
