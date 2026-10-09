#pragma once
#include <atomic>
#include "server/zone/objects/creature/CreatureObject.h"
// Optional XR-session hook. Original clients without a registered XR lease retain
// their native unload path. The pointer is installed by the real live-session bridge.
class SwgxrJtlLifecycle {
 using Handler=void(*)(CreatureObject*);
 static std::atomic<Handler>& callback(){static std::atomic<Handler> value{nullptr};return value;}
public:
 static void install(Handler handler){callback().store(handler);}
 static void disconnect(CreatureObject* c){auto handler=callback().load();if(handler)handler(c);}
};
