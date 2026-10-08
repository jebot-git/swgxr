#ifndef SWGXR_SPICE_ENTERTAINER_H
#define SWGXR_SPICE_ENTERTAINER_H
#include "SwgxrSpice.h"
#include "templates/params/creature/CreaturePosture.h"
class SwgxrSpiceEntertainer {
public:
 static bool blockAttempt(CreatureObject* c){
  if(!c || c->isDead() || c->isIncapacitated() || !SwgxrSpice::withdrawing(c,"neutron_pixey"))return false;
  // The original posture observer also stops an existing performance.
  c->setPosture(CreaturePosture::KNOCKEDDOWN);
  return true;
 }
};
#endif
