#pragma once
#include <algorithm>
#include <cmath>

namespace corecu { namespace regeneration {
// Retain less than one resource point, never an unspent integer healing bank.
// The accumulator is transient and advances only for an eligible, missing pool.
inline int tick(double amount, double& carry, int missing) {
 if (missing <= 0 || !std::isfinite(amount) || amount <= 0.) { carry = 0.; return 0; }
 if (!std::isfinite(carry) || carry < 0. || carry >= 1.) carry = 0.;
 const double total = amount + carry;
 if (total >= missing) { carry = 0.; return missing; }
 // Integer elapsed milliseconds still accumulate small binary rounding errors.
 const int applied = std::min(missing, int(std::floor(total + 1e-9)));
 carry = applied == missing ? 0. : std::max(0., total - applied);
 return applied;
}
} }
