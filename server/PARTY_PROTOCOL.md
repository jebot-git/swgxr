# Native parties from tracked fist bumps

`POST /services/presence` retains its existing singular wallet-hand fields and
accepts optional `hands.left` and `hands.right` objects. Each contains a source
world `position:[x,height,z]` and boolean `tracked`, `fist`, and `free` fields.
The client reports a fist only while grip and trigger are pressed and reports
`free` only when the hand is not operating a held object or interface. Either
hand works, including when the dominant wallet hand is untracked.

A pair must first be observed separated by more than 24 cm or with a released
fist. Both poses must be fresh within one second, in the same native zone/cell,
with bodies within 3 m and hands within 3 m of their own body. Free tracked fists
within 16 cm for 100 ms issue one server-generated contact ID. Initial overlap,
tracking reacquisition while touching, occupied hands, and wallet handshakes do
not issue a party proof. Sustained overlap cannot rearm the contact. Tracking or
native-cell changes invalidate unused contact authorization.

Presence replies add `peers[].group_bump_ready` and `group_bump_id` (24 lowercase
hexadecimal characters). The lower numeric character ID submits:

```
POST /entertainer/group_bump
{character_id, live_session_id, target_id, group_bump_id,
 request_id: "bump_" + group_bump_id, position, zone, building_id, cell_index}
```

The adapter authenticates and consumes the pair-wide proof before allowing the
native action. A consumed proof only permits retries by the same actor with the
same request ID; the opposite player and new request IDs cannot reuse it. The
native durable action receipt precedes movement and membership mutation, so a
lost successful reply can be retried after someone leaves without rejoining
that player. Consumed-proof retries are receipt-only: if the bounded native
receipt ledger has evicted that action, the retry fails closed with
`group_bump_receipt_expired`. A first attempt that never committed also requires
a new gesture after an uncertain retry, rather than recreating consent. Proofs are ephemeral (up to 120 seconds); an adapter restart or an
expired proof requires a new gesture rather than reconstructing consent.

Core3 validates the actual players, same parent/zone, 3 m range, line of sight,
ignore lists, and player state. It calls original GroupManager invitation and
join operations. It does not create a client group or directly fabricate group
membership. Joining through any member uses that group's native leader as the
original invitation source. Two different existing parties cannot merge. The
original group capacity, invitation conflicts, chat, PvP, modifiers and leave
behavior remain native.

For the initial pair, a Squad Leader takes priority; otherwise the higher
native combat level leads, with lower object ID breaking equal-level ties.
Joining ordinary players do not replace the incumbent, regardless of level.
Any member with `outdoors_squadleader_novice` takes leadership automatically.
Among Squad Leaders the highest combat level wins; an incumbent Squad Leader
wins equal-level ties, then the lower object ID breaks remaining ties.
Original create/join/leave/kick/manual-leader paths enforce the same Squad Leader
priority. Original Squad Leader learning/surrender callbacks reconcile it too;
party status also reconciles after other changes to member combat levels.

Entertainer state adds `group:{id,leader_id,members:[{id,name,combat_level,
squad_leader}]}`. Successful bump mutations contain `group_id`, `leader_id` and
a brief `message`. `/entertainer/group_leave` remains the normal leave action.

Validation: `tests/test_party_presence.py` uses a fake monotonic clock for
consent, bounds, expiry, hand selection, pair consumption and replay isolation.
`tools/server/party_native_smoke.py` uses six disposable local native characters,
normal public gesture/action endpoints, and original skill awards solely for
fixture combat-level/profession setup. It leaves groups and saves/logs out every
fixture. It does not access the VPS or launch VR.

The bulk skill-surrender callback is source/build verified; the native fixture
exercises individual surrender and resulting positive group modifiers.
