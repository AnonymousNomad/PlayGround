# ASSET PROVENANCE — BLACK VECTOR INDEPENDENT BENCHMARK
All visual/audio content in this benchmark is PROCEDURAL and PROJECT-OWNED,
generated at runtime by GDScript code. No external art, animation, or audio
files are bundled.

| Asset | Author | Source | License | Acquired | Modifications | Runtime use |
|---|---|---|---|---|---|---|
| Corley humanoid meshes (torso/limbs/head/hair/hands/feet/clothing) | Benchmark team (procedural) | Generated in `scripts/player/corley_rig.gd` via PrimitiveMeshes + vertex-shaped ArrayMeshes | Project-owned, CC0-equivalent | 2026-10-01 | N/A (original) | Third-person player character |
| Corley procedural animation (idle/walk/strafe/jog/crouch/interact/hurt) | Benchmark team | `scripts/player/corley.gd` pose solver | Project-owned | 2026-10-01 | N/A | Bone rotations driven by gait phase |
| NPC humanoids (3 workers) | Benchmark team | Reuses `corley_rig.gd` with male proportions + work clothing palette | Project-owned | 2026-10-01 | Recolored/rescaled | Independent routines |
| Wildlife (fox, hare) | Benchmark team | `scripts/ai/wildlife.gd` procedural quadrupeds | Project-owned | 2026-10-01 | N/A | Ambient sim, flees disturbance |
| Terrain mesh + vertex-color biomes | Benchmark team | `scripts/world/world_builder.gd` height function | Project-owned | 2026-10-01 | N/A | 120x120m island slice |
| Terrain/wood/rock/ground detail textures | Benchmark team | Procedural ImageTexture noise in `world_builder.gd` | Project-owned | 2026-10-01 | N/A | 1K max, tiling |
| Trees (spruce/birch/snag), rocks, grass tufts | Benchmark team | Procedural meshes + MultiMeshInstance3D | Project-owned | 2026-10-01 | N/A | Instanced vegetation |
| Water shader (sea + creek) | Benchmark team | `world_builder.gd` ShaderMaterial, dark cool palette | Project-owned | 2026-10-01 | N/A | Animated normals/spec |
| Cabin + props (walls/roof/door/workbench/crates/stool/fishing gear) | Benchmark team | Procedural boxes/cylinders composed at human scale | Project-owned | 2026-10-01 | N/A | Shelter + field camp |
| Sky/lighting (ProceduralSkyMaterial + fog + tonemap) | Godot engine built-in | Engine resource, configured in code | MIT (engine) | engine | Parameter tuning only | Cool northern daylight |
| All sound (wind/water/steps/fire/door/UI/wildlife) | Benchmark team | `scripts/systems/sound_bank.gd` synthesized AudioStreamWAV | Project-owned | 2026-10-01 | N/A | No music; wilderness soundtrack |
| Fonts/UI icons | Godot default theme + procedural drawing | Engine built-in | MIT | engine | N/A | Minimal HUD |

No CC0 packs were mass-downloaded. No ripped assets. No unknown licenses.
If a future production pass replaces procedural stand-ins with authored art,
record each item here with name/author/URL/license/date/modifications/use.
