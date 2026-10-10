# Original audio integration

All recordings come from the user-provided Total Experience TREs. Public packages contain only code and conversion tools. Preparation preserves source archive/file hashes and explicit failures.

The original-derived client references used here are `GameAnimationMessageCallback.cpp`, `ClientEventManager.cpp`, `CuiSoundManager.cpp` and `GameMusicManager.cpp` at [SWG-Source/client-tools 9494510](https://github.com/SWG-Source/client-tools/tree/949451032647e45e42c3aaef3f41b132c8af36e3/src/engine/client/library/clientGame/src/shared).

| Source | Client trigger |
| --- | --- |
| CDF CSND, CEFT and EVNT; CEF PSND | Native creature/NPC attacks, damage and death; authored animation frame messages |
| ANS MESG event_/hpevent_ | Skeletal footstep and other body events; callbacks never drive tracked poses |
| Terrain family and interior surface tables | Surface-specific footstep sound when supplied, with original generic binding fallback |
| Player CDF footstep bindings | Actual grounded body travel; bounded distance cadence, silent during incap, vehicles, space, jumps and teleports |
| Vehicle VSND damage bands | Idle/run loops and start/stop sounds |
| Shuttle CDF and ANS | Landing/takeoff cues at original frames, attached to animated root |
| Ground environment/interior tables and placed ASND | Regional/day/night/interior ambience and original music cues |
| GMUS ENTR/EXIT/INCP/DETH/WATR | Native combat/life transitions and water coverage; original 5×5 terrain neighborhood rule |
| Ship VSND and interior/environment tables | Engine loops, acceleration/deceleration, POB interiors and authored sector entry music |
| Projectile table fire effects; native hit type effects | Deduplicated fresh ship projectile/shield/armor/component/chassis receipts |
| SENT/SEXI and hyperspace definition | Space combat and hyperspace cues |
| Player UI sound table | Button activation and list selection in desktop and XR panels |

The spatial mixer retains the 32-voice bound; moving actors use at most eight emitters and 16 channels. Event sounds take priority over ambience. Death tails survive replacement of a live actor mesh. Sequence/scene fences prevent native events replaying. Original recordings retain pitch. Existing login, entertainment and voice paths remain separate.

Playback checks cover original creature attacks and footsteps, NPC equipped weapon and death audio, droids, vehicles, both shuttle templates, weapon HRTF/occlusion, regional ambience/day transitions, login music, UI, water, ship engine/interior/fire/shield cues. Linux tests used PulseAudio decoding/mixing, with physical output muted in capture tests. Headless rendering was dummy; these are not headset listening tests. Windows checks use Wine and do not establish native Windows hardware behavior.

Not every audio file has an applicable gameplay event. Blank authored music fields stay silent. Missing original source references remain recorded, including `sound/ui_hover_move.snd`, several NPC voice names and 11 ship CDF references (duplicates included). No guessed replacement recordings are added. Weather simulation and a complete original animation-priority/combat graph remain outside the implemented presentation; bindings alone do not imply those events occur.
