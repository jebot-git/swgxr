-- Ground PvE only. Enabled zones are respected; this does not restore planets.
-- All appearance templates come from the supplied original Core3 deliver_npc.
SwgxrUnderworldBrokers = ScreenPlay:new { numberOfActs = 1 }
registerScreenPlay("SwgxrUnderworldBrokers", true)
function SwgxrUnderworldBrokers:start()
 local brokers = {
  {"tatooine", "Barak", -1039, -3537},
  {"naboo", "Ogden", 1907, 2352},
  {"lok", "Baldwin", 400, 5226},
  {"endor", "Harding", -838, 1617},
  {"dathomir", "Russell", 542, 3053},
 }
 for _, row in ipairs(brokers) do
  if isZoneEnabled(row[1]) then
   local npc = spawnMobile(row[1], "deliver_npc", 1, row[3], 0, row[4], 0, 0)
   if npc ~= nil then
    SceneObject(npc):setCustomObjectName(row[2])
    SceneObject(npc):teleport(row[3], getTerrainHeight(npc, row[3], row[4]), row[4], 0)
    CreatureObject(npc):setOptionsBitmask(264)
   end
  end
 end
end
