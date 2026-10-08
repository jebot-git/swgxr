# Character → VRM extractor

A separate command-line tool for exporting a player's native Core3 character,
current customization, hair, worn equipment and held weapon as one **VRM 1.0**
avatar. It uses the locally prepared SWG assets and the existing Godot character
loader. It does not start the normal game client or change the character's gear.

## Requirements

- A prepared SWGXR checkout, including the user's character/inventory assets under
  `runtime/assets` and the built client GDExtension. Use the project's normal setup
  first; this tool does not download replacement game assets.
- Python 3.10+ and the Godot executable used by this project (`--godot` can specify
  its path). No additional Python packages are required.
- Your local Core3 account, or an existing authenticated HTTPS gateway token.
  A saved character response can also be exported entirely offline.

## Export a character

From the repository root:

```sh
python3 tools/character_export/export_character.py --account YOUR_ACCOUNT
```

Choose a character from the numbered list. The tool writes
`runtime/character_exports/Name-ID.vrm` and a `.vrm.json` conversion report.
If a retained game session prevents account enumeration, use the active
character's ID directly:

```sh
python3 tools/character_export/export_character.py \
  --account YOUR_ACCOUNT --character CHARACTER_ID \
  --output runtime/character_exports/my-avatar.vrm
```

`--list` lists characters without exporting. `--force` explicitly replaces an
existing output. Otherwise existing avatars and reports are preserved.
`--author "Your name"` adds an assembler credit alongside the original asset
credit. Exported game assets remain outside version control.

For a remote gateway, use its HTTPS URL and a file containing an existing token
(the token is sent only in the Authorization header):

```sh
python3 tools/character_export/export_character.py \
  --url https://YOUR_GATEWAY --token-file /path/to/private-token.txt \
  --character CHARACTER_ID --output runtime/character_exports/my-avatar.vrm
```

Alternatively set `SWGXR_EXPORT_TOKEN` in the environment. The tool does not store
the access token in the avatar or report. It keeps TLS verification enabled,
disallows authenticated redirects, and does not send local account queries to a
remote unauthenticated adapter.

Only the existing `GET /characters` and `GET /characters/ID` interfaces are used.
The latter reads native replication; when no session is retained, Core3 can briefly
log in and read the saved scene before disconnecting. A conflicting active session
returns an error; the exporter never stops or replaces that session.

## Offline export

Save a full character endpoint response with this shape:

```json
{
  "backend": "core3",
  "character": {
    "id": "123",
    "name": "My character",
    "race": "human_male",
    "appearance": {
      "race": "human_male",
      "height": 1.0,
      "customization": {},
      "hair": null,
      "source": "core3_replication"
    },
    "equipment": []
  }
}
```

Keep the actual values from the server, including each equipment record's
`template`, `customization`, and `equipped_slots` when present. An explicit empty
equipment array means no equipment; a missing array is rejected.

```sh
python3 tools/character_export/export_character.py \
  --snapshot runtime/my-character-response.json \
  --output runtime/character_exports/offline-avatar.vrm
```

Offline exports reflect the saved snapshot, not later in-game changes. The report
labels this source. Temporary conversion data is private and removed on completion.

## Contents and limits

- Actual customized meshes, equipped appearance and original occlusion rules.
  Clothing hidden beneath another garment may have no visible surface. Core3's
  intrinsic unarmed combat object has no visual model and is omitted explicitly.
- Source skin weights and inverse binds, rebaked to a T-pose with VRM 1.0's +Z
  forward direction. Rigid equipment follows its attachment bone.
- Embedded PNG textures with evaluated palettes, dual-color masks, facial layers,
  alpha cutouts and normal maps. Standard PBR materials are exported; game-world
  lighting is not embedded.
- Required humanoid bones and available optional bones. Species with fewer finger
  joints retain their real joints; missing fingers are not invented.
- No facial expression presets, automatic blinking/lip sync, spring bones or
  gameplay animations in this first version. VRM 0.x-only applications require a
  separate conversion. Original game asset rights remain in effect; the export
  does not grant redistribution rights.

Missing assets, unresolved visible equipment, incomplete humanoid rigs and
unsupported material conversions cause an error rather than a successful partial
avatar. Import the result into your target VRM 1.0 application to verify its
appearance and retargeting there.

## Verification

```sh
python3 -m unittest discover -s tools/character_export -p 'test_*.py' -v
godot --headless --xr-mode off --log-file "$PWD/runtime/character-export-test.log" --path client \
  --script res://tests/character_export_smoke.gd
```

The Python checks exercise the GLB/VRM structure and input/auth boundaries. The
conversion report records source and result hashes, mesh/material/bone counts,
pose policy and errors. Headless tests use the dummy renderer and do not validate
GPU rendering or a live headset.

Format references: [VRM 1.0 specification](https://github.com/vrm-c/vrm-specification/tree/master/specification/VRMC_vrm-1.0),
[Godot GLTFDocument](https://docs.godotengine.org/en/stable/classes/class_gltfdocument.html).
