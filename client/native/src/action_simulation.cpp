#include "action_simulation.h"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstring>
#include <limits>
using namespace godot;
namespace {
constexpr double PI=3.14159265358979323846;
bool finite(const Vector3 &v) { return std::isfinite(v.x)&&std::isfinite(v.y)&&std::isfinite(v.z); }
void u32(std::vector<uint8_t>&b,uint32_t n) { for(int j=0;j<4;++j)b.push_back(uint8_t(n>>(j*8))); }
void f32(std::vector<uint8_t>&b,float n) { uint32_t bits;std::memcpy(&bits,&n,4);u32(b,bits); }
uint32_t read32(const std::vector<uint8_t>&b,size_t at) { return uint32_t(b[at])|(uint32_t(b[at+1])<<8)|(uint32_t(b[at+2])<<16)|(uint32_t(b[at+3])<<24); }
// Swept sphere versus the full segment: fast bolts cannot tunnel through actors.
double sphere_hit(const Vector3 &from,const Vector3 &to,const Vector3 &center,double radius) {
    Vector3 d=to-from,m=from-center;double a=d.length_squared(),c=m.length_squared()-radius*radius;
    if(c<=0)return 0;if(a<1e-12)return 2;double b=m.dot(d),disc=b*b-a*c;
    if(disc<0)return 2;double t=(-b-std::sqrt(disc))/a;return t>=0&&t<=1?t:2;
}
}
void SwgActionSimulation::_bind_methods() {
    ClassDB::bind_method(D_METHOD("configure","options"),&SwgActionSimulation::configure);
    ClassDB::bind_method(D_METHOD("add_actor","position","instance","npc"),&SwgActionSimulation::add_actor);
    ClassDB::bind_method(D_METHOD("submit_command","actor","sequence","velocity","aim","fire"),&SwgActionSimulation::submit_command);
    ClassDB::bind_method(D_METHOD("advance","delta"),&SwgActionSimulation::advance);
    ClassDB::bind_method(D_METHOD("state"),&SwgActionSimulation::state);
    ClassDB::bind_method(D_METHOD("benchmark","options"),&SwgActionSimulation::benchmark);
}
uint32_t SwgActionSimulation::random_u32() { rng^=rng<<13;rng^=rng>>7;rng^=rng<<17;return uint32_t(rng>>16); }
double SwgActionSimulation::random_unit() {return double(random_u32())/4294967296.;}
int64_t SwgActionSimulation::grid_key(int instance,int x,int z) const {return (int64_t(instance)<<40)|(int64_t(uint32_t(x+32768)&65535)<<16)|uint32_t(z+32768);}
void SwgActionSimulation::configure(const Dictionary &o) {
    actors.clear();projectiles.clear();free_projectiles.clear();last_snapshot.clear();commands.clear();packets.clear();shots.clear();grid.clear();
    tick=emitted=hits=wall_hits=expired=pool_overflow=snapshot_bytes=snapshot_packets=snapshot_dropped=snapshot_rejected=commands_dropped=commands_rejected=delivered=isolation_errors=invalid_states=movement_clamps=queue_overflow=dropped_ticks=actor_tests=interest_tests=0;
    peak_projectiles=peak_packets=peak_commands=0;accumulator=0;
    rate=std::clamp(int(o.get("tick_hz",60)),20,240);snapshot_divisor=std::max(1,rate/std::clamp(int(o.get("snapshot_hz",20)),1,rate));input_divisor=std::max(1,rate/30);
    latency_ticks=std::clamp(int(std::round(double(o.get("latency_ms",50.))*rate/1000.)),0,rate*2);
    jitter_ticks=std::clamp(int(std::round(double(o.get("jitter_ms",25.))*rate/1000.)),0,rate);
    loss=std::clamp(double(o.get("loss",.01)),0.,.9);arena=std::clamp(double(o.get("arena_half_extent",128.)),8.,1024.);interest=std::clamp(double(o.get("interest_radius",192.)),8.,2048.);
    max_snapshot_actors=std::clamp(int(o.get("max_snapshot_actors",128)),1,1024);rng=uint64_t(int64_t(o.get("seed",7341)));if(!rng)rng=1;synthetic=bool(o.get("synthetic",false));
    int pool=std::clamp(int(o.get("projectile_capacity",4096)),16,65536);projectiles.resize(pool);for(int i=pool-1;i>=0;--i)free_projectiles.push_back(i);
}
int SwgActionSimulation::add_actor(const Vector3 &position,int instance,bool npc) {
    if(actors.size()>=1024||instance<0||instance>65535||!finite(position))return -1;
    Actor a;a.position=position;a.instance=instance;a.npc=npc;a.aim=Vector3(0,0,-1);actors.push_back(a);last_snapshot.push_back(0);return int(actors.size()-1);
}
bool SwgActionSimulation::submit_command(int id,int sequence,const Vector3 &velocity,const Vector3 &aim,bool fire) {
    if(id<0||size_t(id)>=actors.size()||sequence<=0||!finite(velocity)||!finite(aim))return false;
    Actor&a=actors[id];if(uint32_t(sequence)<=a.sequence){++commands_rejected;return false;}
    a.sequence=sequence;a.velocity=velocity.limit_length(speed);a.velocity.y=0;a.aim=aim.length_squared()>.0001?aim.normalized():a.aim;a.fire=fire;return true;
}
void SwgActionSimulation::rebuild_grid() {
    grid.clear();for(size_t i=0;i<actors.size();++i){const Actor&a=actors[i];grid[grid_key(a.instance,int(std::floor(a.position.x/16)),int(std::floor(a.position.z/16)))].push_back(int(i));}
}
void SwgActionSimulation::synthetic_commands() {
    if(tick%input_divisor)return;
    for(size_t i=0;i<actors.size();++i){Actor&a=actors[i];double phase=double(tick)/rate*.2+i*2.3999632297;
        // Moving continuously while aiming at another actor in the same instance.
        Vector3 velocity=Vector3(std::cos(phase),0,std::sin(phase))*speed;
        Vector3 target=-a.position;for(size_t j=1;j<actors.size();++j){const Actor&other=actors[(i+j)%actors.size()];if(other.instance==a.instance){target=other.position;break;}}
        Command c{int(i),uint32_t(tick+1),velocity,target-a.position,true,tick};
        if(a.npc){submit_command(c.actor,c.sequence,c.velocity,c.aim,c.fire);continue;}
        if(random_unit()<loss){++commands_dropped;continue;}
        c.due=tick+latency_ticks+(jitter_ticks?random_u32()%(jitter_ticks+1):0);
        if(commands.size()<65536)commands.push_back(c);else ++queue_overflow;
    }peak_commands=std::max(peak_commands,commands.size());
}
void SwgActionSimulation::encode_snapshots() {
    for(size_t receiver=0;receiver<actors.size();++receiver){const Actor&r=actors[receiver];if(r.npc)continue;
        std::vector<std::pair<float,int>> nearby;int cells=int(std::ceil(interest/16));int cx=int(std::floor(r.position.x/16)),cz=int(std::floor(r.position.z/16));
        for(int x=cx-cells;x<=cx+cells;++x)for(int z=cz-cells;z<=cz+cells;++z){auto it=grid.find(grid_key(r.instance,x,z));if(it==grid.end())continue;for(int id:it->second){++interest_tests;float d=r.position.distance_squared_to(actors[id].position);if(d<=interest*interest)nearby.emplace_back(d,id);}}
        std::sort(nearby.begin(),nearby.end());if(nearby.size()>size_t(max_snapshot_actors))nearby.resize(max_snapshot_actors);
        Packet packet;packet.receiver=int(receiver);packet.instance=r.instance;packet.sequence=uint32_t(tick+1);packet.due=tick+latency_ticks+(jitter_ticks?random_u32()%(jitter_ticks*2+1):0);
        auto&b=packet.bytes;b.reserve(20+nearby.size()*64+shots.size()*40);u32(b,packet.sequence);u32(b,r.instance);u32(b,uint32_t(receiver));u32(b,uint32_t(nearby.size()));u32(b,0);
        for(auto entry:nearby){int id=entry.second;const Actor&a=actors[id];u32(b,id);u32(b,a.instance);f32(b,a.position.x);f32(b,a.position.y);f32(b,a.position.z);f32(b,a.velocity.x);f32(b,a.velocity.z);
            // 36 encoded bytes reserved for compact head, hand and animation state.
            // Fixture values intentionally zero: this measures serialization/bandwidth, not tracking.
            b.insert(b.end(),36,0);
        }
        uint32_t shot_count=0;for(const Shot&s:shots)if(s.instance==r.instance&&r.position.distance_squared_to(s.position)<=interest*interest){u32(b,s.id);u32(b,s.owner);u32(b,s.instance);f32(b,s.position.x);f32(b,s.position.y);f32(b,s.position.z);f32(b,s.velocity.x);f32(b,s.velocity.y);f32(b,s.velocity.z);u32(b,0);++shot_count;}
        for(int j=0;j<4;++j)b[16+j]=uint8_t(shot_count>>(j*8));
        snapshot_bytes+=b.size();snapshot_packets+=(b.size()+1199)/1200;
        if(random_unit()<loss){++snapshot_dropped;continue;}
        if(packets.size()<65536)packets.push_back(std::move(packet));else ++queue_overflow;
    }peak_packets=std::max(peak_packets,packets.size());shots.clear();
}
void SwgActionSimulation::deliver_packets() {
    for(size_t i=0;i<packets.size();){Packet&p=packets[i];if(p.due>tick){++i;continue;}
        if(p.sequence<=last_snapshot[p.receiver])++snapshot_rejected;
        else {last_snapshot[p.receiver]=p.sequence;++delivered;
            const auto&b=p.bytes;uint32_t count=read32(b,12);if(read32(b,4)!=uint32_t(actors[p.receiver].instance))++isolation_errors;
            for(uint32_t j=0;j<count;++j)if(read32(b,20+j*64+4)!=uint32_t(p.instance))++isolation_errors;
            uint32_t events=read32(b,16);for(uint32_t j=0;j<events;++j)if(read32(b,20+count*64+j*40+8)!=uint32_t(p.instance))++isolation_errors;
        }packets[i]=std::move(packets.back());packets.pop_back();
    }
}
void SwgActionSimulation::step() {
    if(synthetic)synthetic_commands();
    for(size_t i=0;i<commands.size();){const Command c=commands[i];if(c.due>tick){++i;continue;}submit_command(c.actor,c.sequence,c.velocity,c.aim,c.fire);commands[i]=commands.back();commands.pop_back();}
    const double dt=1./rate;
    for(Actor&a:actors){a.position+=a.velocity*dt;
        if(std::abs(a.position.x)>arena){a.position.x=std::clamp<double>(a.position.x,-arena,arena);a.velocity.x=0;++movement_clamps;}
        if(std::abs(a.position.z)>arena){a.position.z=std::clamp<double>(a.position.z,-arena,arena);a.velocity.z=0;++movement_clamps;}
        if(!finite(a.position))++invalid_states;a.cooldown-=dt;
    }rebuild_grid();
    for(size_t i=0;i<actors.size();++i){Actor&a=actors[i];if(!a.fire||a.cooldown>0)continue;a.cooldown+=60./450.;
        if(free_projectiles.empty()){++pool_overflow;continue;}int slot=free_projectiles.back();free_projectiles.pop_back();Projectile&p=projectiles[slot];p.position=a.position;p.velocity=a.aim*90.;p.owner=int(i);p.instance=a.instance;p.life=2.;p.active=true;
        shots.push_back({int(i),a.instance,p.position,p.velocity,uint32_t(++emitted)});
    }
    peak_projectiles=std::max(peak_projectiles,projectiles.size()-free_projectiles.size());
    for(size_t slot=0;slot<projectiles.size();++slot){Projectile&p=projectiles[slot];if(!p.active)continue;Vector3 end=p.position+p.velocity*dt;double nearest=2;int target=-1;
        int minx=int(std::floor((std::min(p.position.x,end.x)-.4)/16)),maxx=int(std::floor((std::max(p.position.x,end.x)+.4)/16));int minz=int(std::floor((std::min(p.position.z,end.z)-.4)/16)),maxz=int(std::floor((std::max(p.position.z,end.z)+.4)/16));
        for(int x=minx;x<=maxx;++x)for(int z=minz;z<=maxz;++z){auto it=grid.find(grid_key(p.instance,x,z));if(it==grid.end())continue;for(int id:it->second){if(id==p.owner)continue;++actor_tests;double t=sphere_hit(p.position,end,actors[id].position,.4);if(t<nearest){nearest=t;target=id;}}}
        bool dead=false;if(target>=0){++hits;dead=true;if(actors[target].instance!=p.instance)++isolation_errors;}
        else if(std::abs(end.x)>arena||std::abs(end.z)>arena){++wall_hits;dead=true;}
        p.position=end;p.life-=dt;if(!dead&&p.life<=0){++expired;dead=true;}if(dead){p.active=false;free_projectiles.push_back(int(slot));}
    }
    if(tick%snapshot_divisor==0)encode_snapshots();deliver_packets();++tick;
}
Dictionary SwgActionSimulation::metrics() const {
    Dictionary d;int players=0,npcs=0;for(const Actor&a:actors)(a.npc? npcs:players)++;
    d["players"]=players;d["npcs"]=npcs;d["ticks"]=int64_t(tick);d["simulated_seconds"]=double(tick)/rate;d["tick_hz"]=rate;d["snapshot_hz"]=double(rate)/snapshot_divisor;
    d["active_projectiles"]=int64_t(projectiles.size()-free_projectiles.size());d["peak_projectiles"]=int64_t(peak_projectiles);d["projectiles_emitted"]=int64_t(emitted);d["actor_hits"]=int64_t(hits);d["arena_wall_hits"]=int64_t(wall_hits);d["expired_projectiles"]=int64_t(expired);d["pool_overflow"]=int64_t(pool_overflow);
    d["snapshot_bytes"]=int64_t(snapshot_bytes);d["snapshot_datagrams_1200_bytes"]=int64_t(snapshot_packets);d["snapshots_lost"]=int64_t(snapshot_dropped);d["stale_snapshots_rejected"]=int64_t(snapshot_rejected);d["snapshots_delivered"]=int64_t(delivered);d["input_commands_lost"]=int64_t(commands_dropped);d["stale_commands_rejected"]=int64_t(commands_rejected);
    d["peak_packet_queue"]=int64_t(peak_packets);d["peak_command_queue"]=int64_t(peak_commands);d["queue_overflow"]=int64_t(queue_overflow);d["instance_isolation_errors"]=int64_t(isolation_errors);d["invalid_states"]=int64_t(invalid_states);d["dropped_ticks"]=int64_t(dropped_ticks);d["movement_boundary_clamps"]=int64_t(movement_clamps);d["actor_sweep_tests"]=int64_t(actor_tests);d["interest_candidate_tests"]=int64_t(interest_tests);
    uint64_t hash=1469598103934665603ULL;for(const Actor&a:actors){for(float value:{a.position.x,a.position.y,a.position.z}){uint32_t bits;std::memcpy(&bits,&value,4);hash^=bits;hash*=1099511628211ULL;}}d["state_checksum"]=String::num_uint64(hash);
    return d;
}
Dictionary SwgActionSimulation::advance(double delta) {
    if(!std::isfinite(delta)||delta<0){Dictionary d;d["valid"]=false;return d;}
    accumulator+=std::min(delta,1.);int available=int(accumulator*rate),count=std::min(available,8);if(available>8){dropped_ticks+=available-8;accumulator-=(available-8)/double(rate);}for(int i=0;i<count;++i){step();accumulator-=1./rate;}return metrics();
}
Dictionary SwgActionSimulation::state() const {Dictionary d=metrics();Array rows;for(size_t i=0;i<actors.size();++i){Dictionary a;a["id"]=int(i);a["position"]=actors[i].position;a["instance_id"]=actors[i].instance;a["npc"]=actors[i].npc;rows.push_back(a);}d["actors"]=rows;return d;}
Dictionary SwgActionSimulation::benchmark(const Dictionary &options) {
    Dictionary o=options.duplicate();o["synthetic"]=true;configure(o);
    const int players=std::clamp(int(o.get("players",16)),1,512),npcs=std::clamp(int(o.get("npcs",32)),0,512),instances=std::clamp(int(o.get("instances",1)),1,64);
    for(int i=0;i<players+npcs;++i){double angle=i*2.3999632297;double radius=std::sqrt(random_unit())*arena*.8;add_actor(Vector3(std::cos(angle)*radius,0,std::sin(angle)*radius),i%instances,i>=players);}
    int warmup=std::clamp(int(o.get("warmup_ticks",120)),0,3600),samples=std::clamp(int(o.get("sample_ticks",1800)),60,36000);for(int i=0;i<warmup;++i)step();
    std::vector<double> times;times.reserve(samples);int over_budget=0,over_headroom=0;auto start=std::chrono::steady_clock::now();
    for(int i=0;i<samples;++i){auto t=std::chrono::steady_clock::now();step();double ms=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-t).count();times.push_back(ms);if(ms>1000./rate)++over_budget;if(ms>8.)++over_headroom;}
    double elapsed=std::chrono::duration<double>(std::chrono::steady_clock::now()-start).count();std::sort(times.begin(),times.end());Dictionary d=metrics();d["kind"]="synthetic_action_simulation";d["real_network"]=false;d["core3_included"]=false;d["actual_stage_geometry"]=false;d["instances"]=instances;d["sample_ticks"]=samples;d["warmup_ticks"]=warmup;d["wall_seconds"]=elapsed;d["tick_p50_ms"]=times[size_t((samples-1)*.50)];d["tick_p95_ms"]=times[size_t((samples-1)*.95)];d["tick_p99_ms"]=times[size_t((samples-1)*.99)];d["tick_max_ms"]=times.back();d["ticks_over_16_67_ms"]=over_budget;d["ticks_over_8_ms"]=over_headroom;
    d["estimated_egress_mbps"]=double(snapshot_bytes)*8./(double(tick)/rate)/1e6;d["per_player_egress_kbps"]=double(snapshot_bytes)*8./(double(tick)/rate)/players/1000.;
    d["correctness_pass"]=isolation_errors==0&&invalid_states==0&&pool_overflow==0&&queue_overflow==0&&dropped_ticks==0&&emitted>0&&delivered>0;d["timing_target_pass"]=times[size_t((samples-1)*.99)]<=8.&&over_budget==0;return d;
}
