// Terrain algorithms adapted from SWGEmu Core3 revision 403893d9.
// AGPL-3.0; attribution and scope in ../TERRAIN_SOURCE.md.
#include "swg_terrain.h"
#include "swg_terrain_noise.h"
#include <algorithm>
#include <array>
#include <cmath>
#include <functional>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <map>
#include <string>
#include <vector>
using namespace godot;
namespace {
float number(const Dictionary &d, const char *key, float fallback = 0) {
    return float(double(d.get(key, fallback)));
}
int integer(const Dictionary &d, const char *key, int fallback = 0) { return int(d.get(key, fallback)); }
bool flag(const Dictionary &d, const char *key, bool fallback = false) { return bool(d.get(key, fallback)); }
std::string string(const Dictionary &d, const char *key) { return String(d.get(key, "")).utf8().get_data(); }
struct P {
    float x = 0, z = 0, h = 0;
};
P point(const Array &a) {
    P p;
    p.x = double(a[0]);
    p.z = double(a[1]);
    if (a.size() > 2)
        p.h = double(a[2]);
    return p;
}
float dist2(P a, P b) {
    float x = a.x - b.x, z = a.z - b.z;
    return x * x + z * z;
}
float feather(float v, int type) {
    switch (type) {
    case 0:
        return v;
    case 1:
        return v * v;
    case 2:
        return std::sqrt(v);
    case 3:
        return v * v * (3 - 2 * v);
    default:
        return 0;
    }
}
float range_filter(float v, float low, float high, float amount) {
    if (v <= low || v >= high)
        return 0;
    float edge = (high - low) * amount * .5f;
    return edge > 0 ? std::min(1.f, std::min(v - low, high - v) / edge) : 1;
}
struct Fractal {
    trn::ptat::Random random;
    std::unique_ptr<PerlinNoise> noise;
    int bias, gain, octaves, combination;
    float bias_value, gain_value, multiplier, amplitude, fx, fz, ox, oz, normalize;
    Fractal(const Dictionary &d) {
        random.setSeed(integer(d, "seed"));
        noise = std::make_unique<PerlinNoise>(&random);
        noise->init();
        bias = integer(d, "bias");
        gain = integer(d, "gain");
        octaves = integer(d, "octaves");
        combination = integer(d, "combination");
        bias_value = number(d, "bias_value");
        gain_value = number(d, "gain_value");
        multiplier = number(d, "frequency_multiplier");
        amplitude = number(d, "amplitude");
        fx = number(d, "frequency_x");
        fz = number(d, "frequency_z");
        ox = number(d, "offset_x");
        oz = number(d, "offset_z");
        float sum = 0, a = 1;
        for (int i = 0; i < octaves; i++) {
            sum += a;
            a *= amplitude;
        }
        normalize = sum != 0 ? 1.f / sum : 0;
    }
    float value(float x, float z) const {
        float xf = x * fx, zf = z * fz;
        float v = 0, f = 1, a = 1;
        for (int i = 0; i < octaves; i++) {
            double p[2] = {double((xf + ox) * f), double((zf + oz) * f)};
            float n = noise->noise2(p);
            double nv = n;
            switch (combination) {
            case 2:
                nv = 1.0 - std::fabs(nv);
                break;
            case 3:
                nv = std::fabs(nv);
                break;
            case 4:
                nv = 1.0 - std::clamp(nv, 0.0, 1.0);
                break;
            case 5:
                nv = std::clamp(nv, 0.0, 1.0);
                break;
            }
            v = nv * a + v;
            f *= multiplier;
            a *= amplitude;
        }
        double result = combination <= 1 ? (v * normalize + 1.0) * .5 : v * normalize;
        if (bias)
            result = std::pow(result, std::log(bias_value) / std::log(.5));
        if (gain) {
            if (result < .001)
                return 0;
            if (result > .999)
                return 1;
            double exponent = std::log(1.0 - gain_value) / std::log(.5);
            result = result < .5 ? std::pow(result * 2, exponent) * .5
                                 : 1.0 - std::pow((1.0 - result) * 2, exponent) * .5;
        }
        return result;
    }
};
struct Rule {
    std::string type, ramp;
    Color color = Color(1, 1, 1, 1);
    bool enabled = true, water = false;
    int feather_type = 0, family = 0, fractal = 0, operation = 0;
    float amount = 0, low = 0, high = 0, height = 0, radius = 0, width = 0, scale = 1, flat = 0,
          water_height = 0;
    P center;
    std::array<float, 4> bounds = {-INFINITY, -INFINITY, INFINITY, INFINITY};
    std::vector<P> points;
    std::vector<std::vector<P>> segments;
    std::vector<bool> flat_segments;
    Rule() = default;
    Rule(const Dictionary &d) {
        type = string(d, "type");
        ramp = string(d, "ramp");
        if (d.has("color")) {
            Array c = d["color"];
            color = Color(double(c[0]) / 255, double(c[1]) / 255, double(c[2]) / 255, 1);
        }
        enabled = flag(d, "enabled", true);
        water = flag(d, "water_enabled");
        water_height = number(d, "water_height");
        feather_type = integer(d, "feather_type");
        family = integer(d, "family");
        fractal = integer(d, "fractal");
        operation = integer(d, "operation");
        amount = number(d, "feather");
        low = number(d, "min");
        high = number(d, "max");
        height = number(d, "height");
        radius = number(d, "radius");
        width = number(d, "width");
        scale = number(d, "scale", 1);
        flat = number(d, "flat_ratio");
        if (d.has("center"))
            center = point(d["center"]);
        Array ps = d.get("points", Array());
        for (int i = 0; i < ps.size(); i++)
            points.push_back(point(ps[i]));
        if (type == "BCIR")
            bounds = {center.x - radius, center.z - radius, center.x + radius, center.z + radius};
        else if (type == "BREC") {
            Array r = d["rect"];
            bounds = {float(double(r[0])), float(double(r[1])), float(double(r[2])), float(double(r[3]))};
            if (bounds[0] > bounds[2])
                std::swap(bounds[0], bounds[2]);
            if (bounds[1] > bounds[3])
                std::swap(bounds[1], bounds[3]);
        } else if (!points.empty()) {
            bounds = {INFINITY, INFINITY, -INFINITY, -INFINITY};
            for (P p : points) {
                bounds[0] = std::min(bounds[0], p.x);
                bounds[1] = std::min(bounds[1], p.z);
                bounds[2] = std::max(bounds[2], p.x);
                bounds[3] = std::max(bounds[3], p.z);
            }
            float expand = (type == "BPLN" || type == "AROA") ? width : 0;
            bounds[0] -= expand;
            bounds[1] -= expand;
            bounds[2] += expand;
            bounds[3] += expand;
        }
        if (type == "BCIR" || type == "BREC")
            amount = std::clamp(amount, 0.f, 1.f);
        Array ss = d.get("segments", Array());
        for (int i = 0; i < ss.size(); i++) {
            Array arr = ss[i];
            std::vector<P> seg;
            float last = 0;
            bool isflat = false;
            for (int j = 0; j < arr.size(); j++) {
                Array p = arr[j];
                P pt;
                pt.x = double(p[0]);
                pt.h = double(p[1]);
                pt.z = double(p[2]);
                isflat = pt.h == last;
                last = pt.h;
                seg.push_back(pt);
            }
            flat_segments.push_back(isflat);
            if (!isflat && seg.size() >= 3) {
                auto original = seg;
                for (size_t j = 1; j + 1 < seg.size(); j++)
                    seg[j].h = (original[j - 1].h + original[j].h + original[j + 1].h) / 3.f;
            }
            segments.push_back(seg);
        }
    }
    bool in_bounds(float x, float z) const {
        return x >= bounds[0] && z >= bounds[1] && x <= bounds[2] && z <= bounds[3];
    }
    bool inside_polygon(float x, float z) const {
        bool inside = false;
        if (points.empty())
            return false;
        P last = points.back();
        for (P p : points) {
            if ((p.z <= z && z < last.z) || (last.z <= z && z < p.z)) {
                if ((z - p.z) * (last.x - p.x) / (last.z - p.z) + p.x > x)
                    inside = !inside;
            }
            last = p;
        }
        return inside;
    }
    float influence(float x, float z) const {
        if (!in_bounds(x, z))
            return 0;
        if (type == "BCIR") {
            float d = dist2(center, {x, z}), rs = radius * radius, inner = (1.0 - amount) * radius;
            float ins = inner * inner;
            return d > rs ? 0 : d > ins ? 1.f - (d - ins) / (rs - ins) : 1;
        }
        if (type == "BREC") {
            if (amount == 0)
                return 1;
            float edge = amount * std::min(bounds[2] - bounds[0], bounds[3] - bounds[1]) * .5;
            return std::min(1.f,
                            std::min({x - bounds[0], bounds[2] - x, z - bounds[1], bounds[3] - z}) / edge);
        }
        if (type == "BPOL" && !inside_polygon(x, z))
            return 0;
        if (type == "BPOL" && amount == 0)
            return 1;
        if (points.empty())
            return 0;
        double d = type == "BPOL" ? double(amount * amount) : double(width * width);
        for (P p : points)
            d = std::min(d, double(dist2(p, {x, z})));
        size_t count = type == "BPOL" ? points.size() : points.size() - 1;
        for (size_t i = 0; i < count; i++) {
            P a = points[i], b = points[(i + 1) % points.size()];
            double dx = b.x - a.x, dz = b.z - a.z, den = dx * dx + dz * dz;
            if (den == 0)
                continue;
            double t = ((x - a.x) * dx + (z - a.z) * dz) / den;
            if (t >= 0 && t <= 1) {
                double ex = x - (a.x + t * dx), ez = z - (a.z + t * dz);
                d = std::min(d, ex * ex + ez * ez);
            }
        }
        if (type == "BPOL") {
            double max = amount * amount;
            return std::abs(d - max) <= .00009999999747378752 ? 1 : std::sqrt(d) / amount;
        }
        if (d >= width * width)
            return 0;
        double inner = (1.0 - amount) * width;
        return d >= inner * inner ? 1.0 - (std::sqrt(d) - inner) / (width - inner) : 1;
    }
};
struct Layer {
    bool enabled = true, invert_bounds = false, invert_filters = false;
    std::vector<Rule> boundaries, filters, affectors;
    std::vector<Layer> children;
    Layer(const Dictionary &d) {
        enabled = flag(d, "enabled", true);
        invert_bounds = flag(d, "invert_boundaries");
        invert_filters = flag(d, "invert_filters");
        for (auto pair : {std::make_pair("boundaries", &boundaries), std::make_pair("filters", &filters),
                          std::make_pair("affectors", &affectors)}) {
            Array a = d.get(pair.first, Array());
            for (int i = 0; i < a.size(); i++)
                pair.second->emplace_back(Dictionary(a[i]));
        }
        Array a = d.get("children", Array());
        for (int i = 0; i < a.size(); i++)
            children.emplace_back(Dictionary(a[i]));
    }
};
struct State {
    Color tint = Color(1, 1, 1, 1);
    float height = 0;
    std::map<int, float> shaders;
    int environment = 0;
    bool excluded = false;
    float slope = 0, direction = 0, dx = 0, dz = 0;
};
} // namespace
struct SwgTerrainEvaluator::Impl {
    std::map<std::string, std::vector<Color>> ramps;
    std::map<int, std::unique_ptr<Fractal>> fractals;
    std::vector<Layer> layers;
    std::vector<Rule> waters;
    std::vector<std::array<float,4>> exclusion_bounds;
    bool global_water = false;
    float water_height = 0;
    float extent = 8192;
    float noise(int id, float x, float z) const {
        auto it = fractals.find(id);
        return it == fractals.end() ? 0 : it->second->value(x, z);
    }
    void collect_water(const Layer &l) {
        if(!l.enabled)return;
        bool exclusion=false;for(const Rule &r:l.affectors)if(r.enabled&&r.type=="AEXC")exclusion=true;
        if(exclusion) {
            if(l.invert_bounds||l.boundaries.empty())exclusion_bounds.push_back({-INFINITY,-INFINITY,INFINITY,INFINITY});
            else for(const Rule &r:l.boundaries)if(r.enabled)exclusion_bounds.push_back(r.bounds);
        }
        for (const Rule &r : l.boundaries)
            if (r.water)
                waters.push_back(r);
        for (const auto &c : l.children)
            collect_water(c);
    }
    static void height_op(State &s, float v, float weight, int op, bool constant) {
        switch (op) {
        case 1:
            s.height += v * weight;
            break;
        case 2:
            s.height -= v * weight;
            break;
        case 3:
            s.height += (v * s.height - s.height) * weight;
            break;
        case 4:
            if (constant)
                s.height = 0;
            break;
        default:
            if (constant)
                s.height = (1.0 - weight) * s.height + weight * v;
            else
                s.height += (v - s.height) * weight;
        }
    }
    static bool road_height(const Rule &r, float x, float z, float &value) {
        if (r.points.size() < 2 || dist2(r.points[0], {x, z}) > 500.f * 500.f)
            return false;
        float width = r.width * .7f;
        for (size_t k = 0; k + 1 < r.points.size(); k++) {
            P first = r.points[k], last = r.points[k + 1];
            float direction = 3.14159265358979323846 / 2 - std::atan2(first.z - last.z, first.x - last.x);
            if (direction < 0)
                direction = 3.14159265358979323846 + (3.14159265358979323846 + direction);
            float half = width / 2;
            double cosine = std::cos(double(direction)), sine = std::sin(double(direction));
            P ll{float(last.x - half * cosine), float(last.z + half * sine)},
                ur{float(first.x + half * cosine), float(first.z - half * sine)};
            P center{(ll.x + ur.x) / 2, (ll.z + ur.z) / 2};
            float road_length = std::sqrt(dist2(ll, ur));
            float dx = center.x - x, dz = center.z - z;
            float rx = dx * std::cos(double(-direction)) + dz * std::sin(double(-direction)),
                  rz = dx * std::sin(double(-direction)) - dz * std::cos(double(-direction));
            if (std::fabs(rx) > half || std::fabs(rz) > road_length / 2)
                continue;
            for (size_t si = 0; si < r.segments.size(); si++) {
                const auto &pts = r.segments[si];
                if (pts.empty() || pts[0].x != first.x || pts[0].z != first.z)
                    continue;
                if (pts.size() < 3 || r.flat_segments[si]) {
                    value = pts[0].h;
                    return true;
                }
                int n = pts.size(), half_size = (n - 1) / 2, segment = -1;
                float h = 0;
                float rs = rz * rz;
                if (dist2(pts.front(), {x, z}) <= dist2(pts.back(), {x, z})) {
                    for (int i = 1; i < n; i++) {
                        if (dist2(pts[i], center) > rs && i <= half_size)
                            continue;
                        segment = i;
                        h = pts[i].h;
                        break;
                    }
                } else {
                    for (int i = n - 1; i > 0; i--) {
                        if (dist2(pts[i], center) > rs && i > half_size)
                            continue;
                        segment = i + 1;
                        h = pts[i].h;
                        break;
                    }
                }
                if (segment > 0 && segment <= n - 1) {
                    P a = pts[segment - 1], b = pts[segment];
                    float distance = std::sqrt(dist2(a, b)), after = std::sqrt(dist2(b, center));
                    float pos = distance - std::fabs(after - std::fabs(rz));
                    if (rz > 0 && half_size + 1 == segment)
                        pos = distance - (after + std::fabs(rz));
                    float ratio = std::clamp(pos / distance, .001f, 1.f);
                    h = a.h + ratio * (b.h - a.h);
                }
                if (h != 0)
                    value = h;
                return true;
            }
            return false;
        }
        return false;
    }
    float filter(const Rule &r, float x, float z, const State &s, bool visual) const {
        if (r.type == "FHGT")
            return range_filter(s.height, r.low, r.high, r.amount);
        if (r.type == "FFRA")
            return range_filter(noise(r.fractal, x, z) * r.scale, r.low, r.high, r.amount);
        // These filters have no height implementation in pinned Core3; they return 0.
        if (!visual)
            return 0;
        if (r.type == "FSLP")
            return range_filter(s.slope, r.low, r.high, std::clamp(r.amount, 0.f, 1.f));
        if (r.type == "FDIR")
            return range_filter(s.direction, r.low, r.high, r.amount);
        if (r.type == "FSHD") {
            auto it = s.shaders.find(r.family);
            return it == s.shaders.end() ? 0 : it->second;
        }
        return 0;
    }
    Color ramp_color(const Rule &r, float x, float z, float height) const {
        auto it = ramps.find(r.ramp);
        if (it == ramps.end() || it->second.empty())
            return Color(1, 1, 1, 1);
        const auto &colors = it->second;
        float t = r.type == "ACRF" ? noise(r.fractal, x, z) : (height - r.low) / (r.high - r.low);
        float position = std::clamp(t, 0.f, 1.f) * (colors.size() - 1);
        int index = position;
        return colors[index].lerp(colors[std::min(index + 1, int(colors.size() - 1))], position - index);
    }
    static void color_blend(State &s, Color value, float weight, int operation) {
        Color target = value;
        if (operation == 1)
            target = s.tint + value;
        else if (operation == 2)
            target = s.tint - value;
        else if (operation == 3)
            target = s.tint * value;
        s.tint = s.tint.lerp(target, std::clamp(weight, 0.f, 1.f));
        s.tint.a = 1;
    }
    static void blend(State &s, int family, float weight) {
        weight = std::clamp(weight, 0.f, 1.f);
        for (auto &kv : s.shaders)
            kv.second *= 1 - weight;
        s.shaders[family] += weight;
    }
    void traverse(const Layer &l, float x, float z, float parent, State &state, bool visual) const {
        if (!l.enabled)
            return;
        float transform = 0;
        bool has = false;
        for (const Rule &r : l.boundaries) {
            if (!r.enabled)
                continue;
            has = true;
            float value = feather(r.influence(x, z), r.feather_type);
            transform = std::max(transform, value);
            if (transform >= 1)
                break;
        }
        if (!has)
            transform = 1;
        if (l.invert_bounds)
            transform = 1 - transform;
        if (transform == 0)
            return;
        for (const Rule &r : l.filters) {
            if (!r.enabled)
                continue;
            transform = std::min(transform, feather(filter(r, x, z, state, visual), r.feather_type));
            if (transform == 0)
                break;
        }
        if (l.invert_filters)
            transform = 1 - transform;
        if (transform == 0)
            return;
        float weight = transform * parent;
        for (const Rule &r : l.affectors) {
            if (!r.enabled)
                continue;
            if (!visual) {
                if (r.type == "AHCN")
                    height_op(state, r.height, weight, r.operation, true);
                else if (r.type == "AHFR")
                    height_op(state, noise(r.fractal, x, z) * r.height, weight, r.operation, false);
                else if (r.type == "AHTR" && r.height > 0) {
                    float remainder = std::fmod(state.height, r.height);
                    if (state.height == 0)
                        remainder += r.height;
                    float base = state.height - remainder, edge = r.height * r.flat + base,
                          top = r.height + base;
                    if (state.height > edge)
                        base = (state.height - edge) / (top - edge) * (top - base) + base;
                    state.height += (base - state.height) * weight;
                } else if (r.type == "AROA")
                    road_height(r, x, z, state.height);
            } else {
                if (r.type == "ASCN")
                    blend(state, r.family, weight);
                else if (r.type == "ACCN")
                    color_blend(state, r.color, weight, r.operation);
                else if (r.type == "ACRF" || r.type == "ACRH")
                    color_blend(state, ramp_color(r, x, z, state.height), weight, r.operation);
                else if (r.type == "AENV")
                    state.environment = r.family;
                else if (r.type == "AEXC" && weight > .5f)
                    state.excluded = true;
                else if (r.type == "AROA") {
                    float ignored = state.height;
                    if (road_height(r, x, z, ignored))
                        blend(state, r.family, weight);
                }
            }
        }
        for (const Layer &child : l.children)
            traverse(child, x, z, weight, state, visual);
    }
    float height(float x, float z) const {
        State s;
        for (const Layer &l : layers)
            traverse(l, x, z, 1, s, false);
        return s.height;
    }
    State evaluate(float x, float z, bool gradient = true) const {
        State s;
        s.height = height(x, z);
        if (gradient) {
            float dx = (height(x + 1, z) - height(x - 1, z)) * .5f,
                  dz = (height(x, z + 1) - height(x, z - 1)) * .5f;
            s.dx = dx;
            s.dz = dz;
            s.slope = std::atan(std::sqrt(dx * dx + dz * dz)) * 180 / 3.14159265358979323846;
            s.direction = std::atan2(dz, dx);
        }
        for (const Layer &l : layers)
            traverse(l, x, z, 1, s, true);
        return s;
    }
    void weights(const State &s, std::array<float, 4> &ids, std::array<float, 4> &values) const {
        std::vector<std::pair<float, int>> weights;
        for (auto kv : s.shaders)
            if (kv.second > 1e-6)
                weights.emplace_back(kv.second, kv.first);
        std::sort(weights.rbegin(), weights.rend());
        float sum = 0;
        for (size_t i = 0; i < 4 && i < weights.size(); i++) {
            ids[i] = weights[i].second;
            values[i] = weights[i].first;
            sum += values[i];
        }
        if (sum > 0)
            for (float &v : values)
                v /= sum;
    }
    bool water(float x, float z, float &h) const {
        for (const Rule &r : waters) {
            if (r.influence(x, z) > 0) {
                h = r.water_height;
                return true;
            }
        }
        if (global_water) {
            h = water_height;
            return true;
        }
        return false;
    }
};
SwgTerrainEvaluator::SwgTerrainEvaluator() = default;
SwgTerrainEvaluator::~SwgTerrainEvaluator() = default;
void SwgTerrainEvaluator::_bind_methods() {
    ClassDB::bind_method(D_METHOD("configure", "manifest"), &SwgTerrainEvaluator::configure);
    ClassDB::bind_method(D_METHOD("sample_height", "swg_x", "swg_z"), &SwgTerrainEvaluator::sample_height);
    ClassDB::bind_method(D_METHOD("sample", "swg_x", "swg_z"), &SwgTerrainEvaluator::sample);
    ClassDB::bind_method(D_METHOD("build_chunk", "swg_min_x", "swg_min_z", "size", "resolution"),
                         &SwgTerrainEvaluator::build_chunk);
}
bool SwgTerrainEvaluator::configure(const Dictionary &manifest) {
    if (impl || !manifest.has("layers") || !manifest.has("fractals"))
        return false;
    auto fresh = std::make_unique<Impl>();
    Dictionary ramps = manifest.get("color_ramps", Dictionary());
    Array ramp_keys = ramps.keys();
    for (int i = 0; i < ramp_keys.size(); i++) {
        String key = ramp_keys[i];
        Dictionary ramp = ramps[key];
        Array colors = ramp["colors"];
        auto &destination = fresh->ramps[key.utf8().get_data()];
        for (int j = 0; j < colors.size(); j++) {
            Array c = colors[j];
            destination.emplace_back(double(c[0]), double(c[1]), double(c[2]), double(c[3]));
        }
    }
    Array fs = manifest["fractals"];
    for (int i = 0; i < fs.size(); i++) {
        Dictionary f = fs[i];
        fresh->fractals[integer(f, "id")] = std::make_unique<Fractal>(f);
    }
    Array ls = manifest["layers"];
    for (int i = 0; i < ls.size(); i++)
        fresh->layers.emplace_back(Dictionary(ls[i]));
    for (const auto &l : fresh->layers)
        fresh->collect_water(l);
    fresh->global_water = flag(manifest, "global_water_enabled");
    fresh->water_height = number(manifest, "global_water_height");
    fresh->extent = number(manifest, "size", 16384) / 2;
    impl = std::move(fresh);
    return true;
}
double SwgTerrainEvaluator::sample_height(double x, double z) const { return impl ? impl->height(x, z) : 0; }
Dictionary SwgTerrainEvaluator::sample(double x, double z) const {
    Dictionary out;
    if (!impl)
        return out;
    State s = impl->evaluate(x, z);
    std::array<float, 4> ids{}, weights{};
    impl->weights(s, ids, weights);
    PackedFloat32Array pi, pw;
    for (int i = 0; i < 4; i++) {
        pi.push_back(ids[i]);
        pw.push_back(weights[i]);
    }
    float water = 0;
    out["height"] = s.height;
    out["terrain_tint"] = s.tint;
    out["shader_ids"] = pi;
    out["shader_weights"] = pw;
    out["environment"] = s.environment;
    out["excluded"] = s.excluded;
    out["water_enabled"] = impl->water(x, z, water);
    out["water_height"] = water;
    return out;
}
Dictionary SwgTerrainEvaluator::build_chunk(double x, double z, double size, int resolution) const {
    Dictionary out;
    if (!impl || resolution < 1 || resolution > 256 || size <= 0)
        return out;
    int n = resolution + 1, count = n * n;
    float step = size / resolution;
    PackedVector3Array vertices, normals;
    PackedVector2Array uv;
    PackedInt32Array indices;
    PackedFloat32Array ids, heights;
    PackedColorArray weights, tints;
    vertices.resize(count);
    normals.resize(count);
    uv.resize(count);
    ids.resize(count * 4);
    weights.resize(count);
    tints.resize(count);
    heights.resize(count);
    std::vector<State> samples(count);
    for (int row = 0; row < n; row++)
        for (int col = 0; col < n; col++) {
            int index = row * n + col;
            float wx = x + col * step, wz = z + row * step;
            State &s = samples[index];
            s = impl->evaluate(wx, wz);
            float dx = s.dx * 2, dz = s.dz * 2;
            vertices[index] = Vector3(col * step, s.height, -row * step);
            normals[index] = Vector3(-dx, 2, dz).normalized();
            uv[index] = Vector2(wx, wz);
            heights[index] = s.height;
            std::array<float, 4> si{}, sw{};
            impl->weights(s, si, sw);
            for (int j = 0; j < 4; j++)
                ids[index * 4 + j] = si[j];
            weights[index] = Color(sw[0], sw[1], sw[2], sw[3]);
            tints[index] = s.tint;
        }
    int holes = 0;
    auto append_sample = [&](const Vector2 &p, const State &state) {
        const int index=vertices.size();
        // Geometry refinement must stay on the original grid surface. Sampling
        // new nonlinear heights here creates vertical T-junction cracks against
        // neighboring unrefined quads. Source rules still determine exclusion.
        const int col=std::clamp(int(std::floor((p.x-x)/step)),0,resolution-1);
        const int row=std::clamp(int(std::floor((p.y-z)/step)),0,resolution-1);
        const double u=std::clamp(double((p.x-x)/step-col),0.0,1.0);
        const double v=std::clamp(double((p.y-z)/step-row),0.0,1.0);
        const int a=row*n+col,b=a+1,c=a+n,d=c+1;
        const double height=u+v<=1.0 ? heights[a]+u*(heights[b]-heights[a])+v*(heights[c]-heights[a])
            : heights[d]+(1.0-v)*(heights[b]-heights[d])+(1.0-u)*(heights[c]-heights[d]);
        vertices.push_back(Vector3(p.x-x,height,z-p.y));
        normals.push_back(Vector3(-state.dx*2,2,state.dz*2).normalized());
        uv.push_back(p);heights.push_back(height);samples.push_back(state);
        std::array<float,4> si{},sw{};impl->weights(state,si,sw);
        for(int j=0;j<4;++j)ids.push_back(si[j]);
        weights.push_back(Color(sw[0],sw[1],sw[2],sw[3]));tints.push_back(state.tint);
        return index;
    };
    std::map<std::pair<int,int>,int> intersections;
    auto intersect = [&](int a,int b) {
        const auto key=std::minmax(a,b);
        auto cached=intersections.find(key);if(cached!=intersections.end())return cached->second;
        Vector2 low=uv[a],high=uv[b];const bool side=samples[a].excluded;
        // Solve the original AEXC rule at the boundary, rather than dropping
        // the entire 2m/4m/16m quad because one corner lies inside the hole.
        for(int i=0;i<14;++i) {
            const Vector2 middle=(low+high)*0.5;
            if(impl->evaluate(middle.x,middle.y).excluded==side)low=middle;else high=middle;
        }
        const Vector2 p=(low+high)*0.5;
        const int result=append_sample(p,impl->evaluate(p.x,p.y));
        intersections[key]=result;return result;
    };
    auto clipped_triangle = [&](int a,int b,int c) {
        const int source[3]={a,b,c};std::vector<int> polygon;
        for(int edge=0;edge<3;++edge) {
            const int first=source[edge],second=source[(edge+1)%3];
            if(!samples[first].excluded)polygon.push_back(first);
            if(samples[first].excluded!=samples[second].excluded)polygon.push_back(intersect(first,second));
        }
        for(size_t i=1;i+1<polygon.size();++i) {
            indices.push_back(polygon[0]);indices.push_back(polygon[i]);indices.push_back(polygon[i+1]);
        }
    };
    std::map<std::pair<float,float>,int> refined;
    auto sample_vertex = [&](const Vector2 &p) {
        const auto key=std::make_pair(float(p.x),float(p.y));auto cached=refined.find(key);
        if(cached!=refined.end())return cached->second;
        const int index=append_sample(p,impl->evaluate(p.x,p.y));refined[key]=index;return index;
    };
    std::function<void(int,int,int,int)> quad;
    quad = [&](int a,int b,int c,int d) {
        bool potential=false;
        for(const auto &bounds:impl->exclusion_bounds)if(uv[d].x>=bounds[0]&&uv[a].x<=bounds[2]&&uv[d].y>=bounds[1]&&uv[a].y<=bounds[3]) {potential=true;break;}
        const bool all_same=samples[a].excluded==samples[b].excluded && samples[a].excluded==samples[c].excluded && samples[a].excluded==samples[d].excluded;
        if(!potential) {clipped_triangle(a,c,b);clipped_triangle(b,c,d);return;}
        const Vector2 middle=(uv[a]+uv[d])*0.5;
        const int center=sample_vertex(middle);
        if(all_same && samples[a].excluded && samples[center].excluded) {holes++;return;}
        // Refine only original exclusion bounds. Identical 12.5cm boundary
        // sampling at every LOD prevents independently eroded neighboring tiles.
        if(uv[b].x-uv[a].x>0.1251) {
            const int ab=sample_vertex((uv[a]+uv[b])*0.5),ac=sample_vertex((uv[a]+uv[c])*0.5);
            const int bd=sample_vertex((uv[b]+uv[d])*0.5),cd=sample_vertex((uv[c]+uv[d])*0.5);
            quad(a,ab,ac,center);quad(ab,b,center,bd);quad(ac,center,c,cd);quad(center,bd,cd,d);return;
        }
        if(samples[a].excluded||samples[b].excluded||samples[c].excluded||samples[d].excluded||samples[center].excluded)holes++;
        if(all_same && samples[a].excluded!=samples[center].excluded) {
            clipped_triangle(a,c,center);clipped_triangle(c,d,center);clipped_triangle(d,b,center);clipped_triangle(b,a,center);
        } else {clipped_triangle(a,c,b);clipped_triangle(b,c,d);}
    };
    for(int row=0;row<resolution;++row)for(int col=0;col<resolution;++col) {
        const int a=row*n+col,b=a+1,c=a+n,d=c+1;quad(a,b,c,d);
    }
    out["vertices"] = vertices;
    out["normals"] = normals;
    out["uvs"] = uv;
    out["indices"] = indices;
    out["shader_ids"] = ids;
    out["shader_weights"] = weights;
    out["tints"] = tints;
    out["heights"] = heights;
    out["excluded_cells"] = holes;
    out["exclusion_boundary_vertices"] = int(intersections.size());
    out["exclusion_boundary_precision_m"] = 0.125 / 16384.0;
    out["exclusion_boundary_sampling_m"] = 0.125;
    out["resolution"] = resolution;
    out["size"] = size;
    out["swg_min_x"] = x;
    out["swg_min_z"] = z;
    return out;
}
