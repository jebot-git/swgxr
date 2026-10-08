#ifndef SWG_TERRAIN_H
#define SWG_TERRAIN_H
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <memory>
namespace godot {
class SwgTerrainEvaluator : public RefCounted {
    GDCLASS(SwgTerrainEvaluator, RefCounted)
    struct Impl;
    std::unique_ptr<Impl> impl;

  protected:
    static void _bind_methods();

  public:
    SwgTerrainEvaluator();
    ~SwgTerrainEvaluator();
    bool configure(const Dictionary &manifest);
    double sample_height(double swg_x, double swg_z) const;
    Dictionary sample(double swg_x, double swg_z) const;
    Dictionary movement_sample(double swg_x, double swg_z) const;
    Dictionary build_chunk(double swg_min_x, double swg_min_z, double size, int resolution) const;
};
} // namespace godot
#endif
