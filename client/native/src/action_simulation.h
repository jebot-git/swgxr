#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <vector>
#include <unordered_map>
#include <deque>
#include <cstdint>
namespace godot {
// Synthetic transport and arena are benchmark fixtures, not a Core3/network server.
// Actor/projectile pools, fixed stepping and sequencing are reusable simulation code.
class SwgActionSimulation : public RefCounted {
    GDCLASS(SwgActionSimulation, RefCounted)
    struct Actor { Vector3 position, velocity, aim; int instance=0; bool npc=false,fire=false; uint32_t sequence=0; double cooldown=0; };
    struct Projectile { Vector3 position,velocity; int owner=-1,instance=0; double life=0; bool active=false; };
    struct Command { int actor; uint32_t sequence; Vector3 velocity,aim; bool fire; uint64_t due; };
    struct Packet { int receiver,instance; uint32_t sequence; uint64_t due; std::vector<uint8_t> bytes; };
    struct Shot { int owner,instance; Vector3 position,velocity; uint32_t id; };
    std::vector<Actor> actors;
    std::vector<Projectile> projectiles;
    std::vector<int> free_projectiles;
    std::vector<uint32_t> last_snapshot;
    std::vector<Command> commands;
    std::vector<Packet> packets;
    std::vector<Shot> shots;
    std::unordered_map<int64_t,std::vector<int>> grid;
    uint64_t tick=0, rng=1, emitted=0,hits=0,wall_hits=0,expired=0,pool_overflow=0, snapshot_bytes=0,snapshot_packets=0,snapshot_dropped=0,snapshot_rejected=0,commands_dropped=0,commands_rejected=0, delivered=0,isolation_errors=0,invalid_states=0, movement_clamps=0, queue_overflow=0, dropped_ticks=0, actor_tests=0,interest_tests=0;
    size_t peak_projectiles=0,peak_packets=0,peak_commands=0;
    int rate=60,snapshot_divisor=3,input_divisor=2,latency_ticks=3,jitter_ticks=1,max_snapshot_actors=128;
    double loss=.01, arena=128,interest=192,speed=7.5,accumulator=0;
    bool synthetic=false;
    uint32_t random_u32();
    double random_unit();
    int64_t grid_key(int instance,int x,int z) const;
    void rebuild_grid();
    void step();
    void encode_snapshots();
    void deliver_packets();
    void synthetic_commands();
    Dictionary metrics() const;
protected:
    static void _bind_methods();
public:
    void configure(const Dictionary &options);
    int add_actor(const Vector3 &position,int instance,bool npc);
    bool submit_command(int actor,int sequence,const Vector3 &velocity,const Vector3 &aim,bool fire);
    Dictionary advance(double delta);
    Dictionary state() const;
    Dictionary benchmark(const Dictionary &options);
};
}
