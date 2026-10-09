// Dependency isolation for existing non-BH profession launch/impact fixtures.
// BH implementation is exercised separately by bounty_combat_native.cpp.
struct SwgxrBountyHunter {
 static bool compatible(CreatureObject*,const std::string& =""){return false;}
 static bool learned(CreatureObject*,const std::string&){return false;}
 static bool lightning(Weapon*){return false;}static bool scatter(Weapon*){return false;}
 static int branch(CreatureObject*,const std::string&){return 0;}
 static double cooldown(CreatureObject*,const std::string&){return 0;}
 static void recover(CreatureObject*,const std::string&){}
 static bool targetReady(CreatureObject*,const std::string&){return false;}
 static void effects(CreatureObject*,CreatureObject*,const std::string&,int){}
 static Json projectileProfile(Weapon*){return Json::object();}
};
struct SwgxrBlastSight {static bool clear(CreatureObject*,CreatureObject* a,const corecu::bountyhunter::Vec&){return a->los;}};
