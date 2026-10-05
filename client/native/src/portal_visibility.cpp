#include "portal_visibility.h"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <algorithm>
#include <cmath>
using namespace godot;
void SwgPortalVisibility::_bind_methods() {
    ClassDB::bind_method(D_METHOD("configure", "definitions"), &SwgPortalVisibility::configure);
    ClassDB::bind_method(D_METHOD("solve", "views", "margin", "budget"), &SwgPortalVisibility::solve, DEFVAL(0.25), DEFVAL(8192));
}
void SwgPortalVisibility::configure(const Dictionary &definitions) {
    cells.clear(); buildings.clear(); indices.clear(); configured = false;
    // Malformed or excessive input must never become a reason to hide geometry.
    if (definitions.size() > 32768) return;
    Array keys = definitions.keys(); Dictionary building_indices;
    for (int i = 0; i < keys.size(); ++i) {
        Dictionary data = definitions[keys[i]]; int64_t bid = data.get("building_object_id", 0);
        if (!building_indices.has(bid)) { building_indices[bid] = int(buildings.size()); Building b; b.id = bid; buildings.push_back(b); }
        Cell cell; cell.id = keys[i]; cell.building = building_indices[bid]; cell.exterior = data.get("is_exterior", false);
        indices[cell.id] = int(cells.size()); buildings[cell.building].cells.push_back(cells.size());
        if (cell.exterior) buildings[cell.building].roots.push_back(cells.size());
        cells.push_back(cell);
    }
    for (int i = 0; i < int(cells.size()); ++i) {
        Dictionary data = definitions[cells[i].id]; Array portals = data.get("portals", Array());
        auto &building = buildings[cells[i].building];
        if (portals.size() > 128 || building.id <= 0) { building.valid = false; continue; }
        for (int j = 0; j < portals.size(); ++j) {
            Dictionary p = portals[j]; String next = p.get("leads_to", "");
            PackedVector3Array vertices = p.get("world_vertices", PackedVector3Array());
            if (!indices.has(next) || vertices.size() < 3 || vertices.size() > 64) { building.valid = false; continue; }
            Portal portal; portal.target = indices[next];
            if (cells[portal.target].building != cells[i].building) { building.valid = false; continue; }
            for (int k = 0; k < vertices.size(); ++k) {
                if (!vertices[k].is_finite()) building.valid = false;
                portal.vertices.push_back(vertices[k]);
            }
            Vector3 normal = (vertices[1]-vertices[0]).cross(vertices[2]-vertices[0]);
            if (normal.length_squared() < 1e-12) building.valid = false;
            else {
                normal.normalize(); double sign = 0;
                for (int k = 0; k < vertices.size(); ++k) {
                    if (std::abs(normal.dot(vertices[k]-vertices[0])) > 0.01) building.valid = false;
                    double cross = (vertices[(k+1)%vertices.size()]-vertices[k]).cross(vertices[(k+2)%vertices.size()]-vertices[(k+1)%vertices.size()]).dot(normal);
                    if (std::abs(cross) > 1e-6) { if (sign*cross < 0) building.valid = false; sign = cross; }
                }
            }
            cells[i].portals.push_back(std::move(portal));
        }
    }
    for (auto &building : buildings) if (building.roots.empty()) building.valid = false;
    // Partial graphs are fail-open, including an absent reciprocal connection.
    for (int i = 0; i < int(cells.size()); ++i) for (const auto &portal : cells[i].portals) {
        bool reciprocal = false;
        for (const auto &back : cells[portal.target].portals) if (back.target == i) reciprocal = true;
        if (!reciprocal) buildings[cells[i].building].valid = false;
    }
    configured = true;
}
std::vector<Vector3> SwgPortalVisibility::clip(const std::vector<Vector3> &polygon, const Plane &plane) {
    std::vector<Vector3> out; if (polygon.empty()) return out;
    Vector3 previous = polygon.back(); double pd = plane.distance_to(previous);
    for (const auto &point : polygon) {
        double d = plane.distance_to(point); bool inside = d >= -0.001, prev_inside = pd >= -0.001;
        if (inside != prev_inside && std::abs(pd-d) > 1e-10) out.push_back(previous.lerp(point, pd/(pd-d)));
        if (inside) out.push_back(point);
        previous = point; pd = d;
    }
    return out;
}
bool SwgPortalVisibility::walk(int index, const Vector3 &eye, const std::vector<Plane> &planes, std::vector<int> &path,
    std::vector<bool> &visible, double margin, int &visits, int budget) const {
    if (++visits > budget || path.size() > 32 || planes.size() > 256) return false;
    visible[index] = true;
    for (const auto &portal : cells[index].portals) {
        if (std::find(path.begin(), path.end(), portal.target) != path.end()) continue;
        auto polygon = portal.vertices;
        Plane portal_plane(polygon[0], polygon[1], polygon[2]);
        const bool near = std::abs(portal_plane.distance_to(eye)) <= margin;
        if (!near) for (const auto &plane : planes) { polygon = clip(polygon, plane); if (polygon.size() < 3) break; }
        if (polygon.size() < 3) continue;
        auto next_planes = planes;
        if (!near) {
            Vector3 center; for (const auto &p : polygon) center += p; center /= polygon.size();
            for (size_t k = 0; k < polygon.size(); ++k) {
                Vector3 normal = (polygon[k]-eye).cross(polygon[(k+1)%polygon.size()]-eye);
                if (normal.length_squared() < 1e-12) continue;
                Plane edge(normal.normalized(), eye);
                if (edge.distance_to(center) < 0) edge = -edge;
                edge.d -= margin; next_planes.push_back(edge);
            }
            if (portal_plane.distance_to(eye) > 0) portal_plane = -portal_plane;
            portal_plane.d -= margin; next_planes.push_back(portal_plane);
        }
        path.push_back(portal.target);
        if (!walk(portal.target, eye, next_planes, path, visible, margin, visits, budget)) return false;
        path.pop_back();
    }
    return true;
}
Dictionary SwgPortalVisibility::solve(const Array &views, double margin, int budget) const {
    Dictionary result, visible_ids; std::vector<bool> visible(cells.size(), false);
    int visits = 0, fail_open_buildings = 0; bool all_open = !configured || views.is_empty() || views.size() > 8;
    margin = std::clamp(margin, 0.05, 2.0); budget = std::clamp(budget, 1, 65536);
    for (int b = 0; b < int(buildings.size()); ++b) {
        const auto &building = buildings[b]; bool valid = !all_open && building.valid;
        for (int v = 0; valid && v < views.size(); ++v) {
            Dictionary view = views[v]; Vector3 eye = view.get("position", Vector3()); String cell_id = view.get("cell_id", "");
            if (!eye.is_finite() || (!cell_id.is_empty() && !indices.has(cell_id))) { valid = false; break; }
            std::vector<int> starts = building.roots;
            if (indices.has(cell_id)) { int index = indices[cell_id]; if (cells[index].building == b) starts = {index}; }
            for (int start : starts) {
                std::vector<int> path = {start};
                if (!walk(start, eye, {}, path, visible, margin, visits, budget)) { valid = false; break; }
            }
        }
        if (!valid) { ++fail_open_buildings; for (int index : building.cells) visible[index] = true; }
        // Exterior meshes can cover whole buildings; retain them for shader clipping.
        for (int index : building.roots) visible[index] = true;
    }
    for (int i = 0; i < int(cells.size()); ++i) if (visible[i]) visible_ids[cells[i].id] = true;
    result["visible_cells"] = visible_ids; result["known_cells"] = int(cells.size()); result["visible_cell_count"] = visible_ids.size();
    result["visits"] = visits; result["fail_open_buildings"] = fail_open_buildings; result["buildings"] = int(buildings.size());
    result["complete"] = configured && !all_open && fail_open_buildings == 0; result["budget"] = budget; result["margin"] = margin;
    return result;
}
