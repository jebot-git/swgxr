#include "cell_classifier.h"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <limits>
#include <cmath>

namespace godot {
void SwgCellClassifier::_bind_methods() {
    ClassDB::bind_method(D_METHOD("configure", "definitions"), &SwgCellClassifier::configure);
    ClassDB::bind_method(D_METHOD("classify", "position"), &SwgCellClassifier::classify);
    ClassDB::bind_method(D_METHOD("advance", "from", "to", "current_cell"), &SwgCellClassifier::advance);
}

void SwgCellClassifier::configure(const Dictionary &definitions) {
    cells.clear();
    const Array keys = definitions.keys();
    for (int64_t i = 0; i < keys.size(); ++i) {
        const Dictionary source = definitions[keys[i]];

        const Array vertices = source.get("floor_vertices", Array());
        const Array indices = source.get("floor_indices", Array());
        const Array minimum = source.get("bounds_min", Array());
        const Array maximum = source.get("bounds_max", Array());
        if (vertices.size() % 3 || indices.size() % 3 || minimum.size() != 3 || maximum.size() != 3) continue;
        Cell cell;
        cell.id = keys[i];
        cell.exterior = bool(source.get("is_exterior", false));
        const Array portals = source.get("portals", Array());
        for (int64_t pi=0; pi<portals.size(); ++pi) {
            const Dictionary p = portals[pi];
            if (!bool(p.get("passable", false)) || bool(p.get("source_disabled", false))) continue;
            const Array points = p.get("vertices", Array());
            Portal portal; portal.target = p.get("leads_to", String());
            for (int64_t v=0; v+2<points.size(); v+=3) portal.vertices.push_back(Vector3(points[v],points[v+1],points[v+2]));
            if (portal.vertices.size()>=3 && !portal.target.is_empty()) cell.portals.push_back(portal);
        }
        cell.name = source.get("name", String());
        cell.building_id = source.get("building_object_id", int64_t(0));
        cell.minimum = Vector3(minimum[0], minimum[1], minimum[2]);
        cell.maximum = Vector3(maximum[0], maximum[1], maximum[2]);
        for (int64_t j = 0; j < indices.size(); j += 3) {
            Vector3 points[3];
            bool valid = true;
            for (int k = 0; k < 3; ++k) {
                const int64_t index = indices[j + k];
                if (index < 0 || index >= vertices.size() / 3) { valid = false; break; }
                points[k] = Vector3(vertices[index * 3], vertices[index * 3 + 1], vertices[index * 3 + 2]);
            }
            if (valid) cell.floor.push_back({points[0], points[1], points[2]});
        }
        if (!cell.floor.empty() || !cell.portals.empty()) cells.push_back(std::move(cell));
    }
}

Dictionary SwgCellClassifier::classify(const Vector3 &position) const {
    const Cell *best = nullptr;
    double best_height = -std::numeric_limits<double>::infinity();
    for (const Cell &cell : cells) {
        if (position.x < cell.minimum.x - 0.02 || position.x > cell.maximum.x + 0.02 ||
            position.z < cell.minimum.z - 0.02 || position.z > cell.maximum.z + 0.02 ||
            position.y < cell.minimum.y - 0.6 || position.y > cell.maximum.y + 0.1) continue;
        for (const Triangle &triangle : cell.floor) {
            const Vector3 u = triangle.b - triangle.a, v = triangle.c - triangle.a, p = position - triangle.a;
            const double determinant = u.x * v.z - v.x * u.z;
            if (std::abs(determinant) < 1e-8) continue;
            const double b = (p.x * v.z - v.x * p.z) / determinant;
            const double c = (u.x * p.z - p.x * u.z) / determinant;
            if (b < -1e-5 || c < -1e-5 || b + c > 1.00001) continue;
            const double height = triangle.a.y + b * u.y + c * v.y;
            // Allow capsule support margin/step approach, but not underground or roofs.
            if (height > position.y + 0.15 || height < position.y - 0.75 || height < best_height) continue;
            best_height = height;
            best = &cell;
        }
    }
    Dictionary result;
    if (best && !best->exterior) {
        result["cell_id"] = best->id;
        result["name"] = best->name;
        result["building_object_id"] = best->building_id;
    }
    return result;
}

Dictionary SwgCellClassifier::advance(const Vector3 &from, const Vector3 &to, const String &current_cell) const {
    String state = current_cell;
    const Vector3 start = from;
    const Vector3 motion = to-from;
    double consumed = -0.00001;
    for (int crossing=0; crossing<8; ++crossing) {
        double nearest = 2.0;
        String target;
        for (const Cell &cell : cells) {
            if (state.is_empty() ? !cell.exterior : cell.id != state) continue;
            for (const Portal &portal : cell.portals) {
                const Vector3 normal=(portal.vertices[1]-portal.vertices[0]).cross(portal.vertices[2]-portal.vertices[0]).normalized();
                const double denominator=normal.dot(motion);
                if (std::abs(denominator)<1e-8) continue;
                const double t=normal.dot(portal.vertices[0]-start)/denominator;
                if (t<0.00001 || t<=consumed+0.000001 || t>1.00001 || t>=nearest) continue;
                const Vector3 point=start+motion*t;
                bool inside=true;
                double sign=0;
                for (size_t i=0;i<portal.vertices.size();++i) {
                    const double edge=(portal.vertices[(i+1)%portal.vertices.size()]-portal.vertices[i]).cross(point-portal.vertices[i]).dot(normal);
                    if (std::abs(edge)<1e-5) continue;
                    if (sign==0) sign=edge;
                    else if (sign*edge<0) {inside=false;break;}
                }
                if (inside) {nearest=t;target=portal.target;}
            }
        }
        if (target.is_empty()) break;
        state=target;
        // Keep the original segment and advance a double-precision parameter.
        // A fractional world-position nudge can vanish at SWG coordinates in
        // float32, repeatedly crossing the reciprocal portal in the same call.
        consumed=nearest;
        for (const Cell &cell : cells) if(cell.id==state && cell.exterior) {state=String();break;}
        if (consumed>=1.0) break;
    }
    Dictionary result;
    for (const Cell &cell : cells) if (cell.id==state && !cell.exterior) {
        result["cell_id"]=cell.id;result["name"]=cell.name;result["building_object_id"]=cell.building_id;break;
    }
    return result;
}
}
