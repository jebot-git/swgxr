# Native NPC speech and passive comprehension

Actual Core3 `ChatManager::broadcastChatMessage` deliveries feed the recipient's
private `snapshot.player.npc_speech`. Both plain and original StringId overloads
retain their native range and target/group restrictions. The existing authenticated
`/session/sync` exposes that owner's normalized speech envelope; no client command
can generate exposure, progress or skills.

The envelope contains a monotonically increasing `sequence`, at most 32 recent
`events`, and the eleven original `languages`. Events have a decimal string `id`,
`actor_id`, localized `name`, original world `position`, `zone`, `building_id`,
`cell_index`, `language_id`, `language_key`, `language_name`, presentation `text`,
`understood`, `comprehension_before`/`comprehension_after` percentages, `age_ms`,
and a 6000 ms `lifetime_ms`. Raw StringId parameters and untranslated unknown
speech are removed before the response is cached. Repeated sync advances age;
it neither renews bubbles nor awards another exposure.

Each qualifying native NPC speech event gives 250 basis points (2.5 percentage
points), once per recipient and event, capped at 10000. Forty exposures from zero
award the existing `social_language_*_comprehend` skill through Core3's SkillManager.
Speaking skills remain separate and are never granted by listening. Original
species starting skills are respected. Inaudible Lekku does not grant hearing
progress and unknown Lekku displays an unfamiliar-body-language indication.

Recipients must be online, scene-ready, living, within both the original speech
range and 32 m, in the same zone and cell, with native line of sight. The native
broadcast selects recipients first; a short queued receipt task revalidates these
conditions while holding only the speaker/recipient lock pair. Event time is
captured at the broadcast hook; queued receipts six seconds old are discarded.
Duplicate receipts are fenced by a bounded persistent ID journal. Progress,
completed original skills and the journal use the real PlayerObject persistence;
no client JSON store or client acknowledgement grants anything.

Speech presentation follows the original game-language table's deterministic
ASCII letter-to-syllable substitution, with the original case/punctuation
behavior. Partial progress does not reveal words. One narrow original NGE typo
is corrected: the table's `i` column is used rather than loading `h` twice.

A server-owned presence task checks every 20 seconds and selects at most one
eligible nearby peaceful humanoid. Each selected NPC has a shared 90-second
ambient cooldown. It emits only source-catalogued `hi_mid_N` greetings through
ChatManager. Authored reaction tables retain their personality; a peaceful
`townsperson` with no authored table or conversation uses the original townperson
greetings as an explicit prototype fallback. Combatants, pets, monsters and
quest-conversation NPCs are excluded from that fallback. Existing generic native
reactions use the NPC's source species language; explicit screenplay languages
remain unchanged. Trusted `spatialChat(npc, text_or_stringid, languageID)` accepts
an optional third argument; existing two-argument calls remain Basic.

`tools/assets/prepare_chatter.py` exports ignored source media data and hashes to
`runtime/assets/chatter/catalog.json`. Core3 reads this prepared catalogue once
at startup, with optional `SWGXR_CHATTER_CATALOG_PATH`. Missing/invalid catalogues
produce a clear native warning and disable this feature; original chat delivery
continues. Restart after correcting the prepared catalogue.

`tools/server/chatter_smoke.py` uses isolated fresh human listeners and original
administrator-spawned NPCs. Explicit native speech is labelled fixture setup;
it does not impersonate naturally occurring dialogue. Natural server-timer
speech is checked separately. No VR or VPS changes are part of this validation.

Validation: `runtime/evidence/chatter-native.json` records 23 passing native
checks (21 speech checks and two full-process-restart persistence checks), including two-speaker/two-listener concurrency, the exact 39-to-40
comprehension threshold, partial and completed persistence, source parameter
resolution, hearing eligibility and genuine timer-driven commoner speech.
An additional administrator cell-transfer probe exposed the existing native
world snapshot's null-zone dereference. The snapshot now returns
`native_player_zone_unavailable` during that state instead of terminating Core3.
That cell/occlusion probe was stopped and is not counted as runtime validation;
those filters remain source-checked. Diagnostic details are retained in
`runtime/evidence/chatter-boundary-blocker.json`.
