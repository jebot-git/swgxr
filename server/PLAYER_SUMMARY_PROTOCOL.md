# Owner player summary

Patch0077 adds `snapshot.player.player_summary` to the existing native live
snapshot. The same native getters are read on the existing non-live session
status request. `GET /datapad` and the `/enter` datapad object expose the result
as top-level `player_summary`. No additional native poll or area scan is needed.
A missing older-server summary is `null`, not invented zero statistics.

Version1 contains:

- `character_id`, `name`, primary `ham`, `max_ham`, `wounds` arrays in health,
  action, mind order, and `shock_wounds`.
- `wallet.cash`, `wallet.bank` from the real creature balances.
- `faction.allegiance`, numeric `status`, `status_name`, `rank`, `pending_status`
  and `standings.imperial` / `standings.rebel`.
- `homepoints.residence` and `homepoints.cloning`, using the exact native
  PlayerObject references read by original `CharacterSheetResponseMessage`.
  Each includes string `id` and `status`: `unset` for reference0, `unavailable`
  for a nonzero unresolved/unzoned reference, or `available` with `name`,
  original `template`, `zone`, and `[worldX,height,worldY]` `position`.
- `armour.movement_scale`, `output_scale`, `recovery_scale`, native revision and
  `pieces`. Each unique equipped armour object has `id`, `name`, `template`,
  `slots`, original `rating`, `broken`, `shield`, `protection_percent` channels
  and converted `protection_score` channels when that original item participates
  in the current armour conversion. Protection is per piece/body slot; the
  summary does not invent an aggregate percentage by adding worn pieces.

Native string IDs for armour/home names are resolved using the supplied original
STF tables. IDs, values and coordinates are unchanged. Python projection rejects
an owner mismatch and makes an independent copy of the native snapshot.

`POST /inventory/unequip` is now exposed by the authenticated public gateway.
It uses the existing native equipped-item ownership, capacity, slicing lease and
state checks, and returns the existing fresh inventory verification envelope.
Dragging equipment must remain a visual preview until that authoritative
operation succeeds.
